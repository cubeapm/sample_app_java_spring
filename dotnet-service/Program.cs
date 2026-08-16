using System.Text;
using Confluent.Kafka;
using MySqlConnector;
using Npgsql;
using RabbitMQ.Client;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient();

const string Service = "dotnet";
var topics = new HashSet<string> { "topic-1", "topic-2" };
var peers = new Dictionary<string, string>
{
    ["java"] = Environment.GetEnvironmentVariable("JAVA_SERVICE_URL") ?? "http://java-host:8000",
    ["nodejs"] = Environment.GetEnvironmentVariable("NODE_SERVICE_URL") ?? "http://node-host:8001",
    ["python"] = Environment.GetEnvironmentVariable("PYTHON_SERVICE_URL") ?? "http://python-host:8002",
    ["php"] = Environment.GetEnvironmentVariable("PHP_SERVICE_URL") ?? "http://php-host:8003",
};

var mysqlHost = Environment.GetEnvironmentVariable("MYSQL_HOST") ?? "mysql-host";
var mysqlPort = Environment.GetEnvironmentVariable("MYSQL_PORT") ?? "3306";
var mysqlUser = Environment.GetEnvironmentVariable("MYSQL_USER") ?? "root";
var mysqlPassword = Environment.GetEnvironmentVariable("MYSQL_PASSWORD") ?? "root";
var mysqlDatabase = Environment.GetEnvironmentVariable("MYSQL_DATABASE") ?? "test";
var postgresHost = Environment.GetEnvironmentVariable("POSTGRES_HOST") ?? "postgres-host";
var postgresPort = Environment.GetEnvironmentVariable("POSTGRES_PORT") ?? "5432";
var postgresUser = Environment.GetEnvironmentVariable("POSTGRES_USER") ?? "root";
var postgresPassword = Environment.GetEnvironmentVariable("POSTGRES_PASSWORD") ?? "root";
var postgresDatabase = Environment.GetEnvironmentVariable("POSTGRES_DATABASE") ?? "test";
var redisHost = Environment.GetEnvironmentVariable("REDIS_HOST") ?? "redis-host";
var redisPort = Environment.GetEnvironmentVariable("REDIS_PORT") ?? "6379";
var kafkaBrokers = Environment.GetEnvironmentVariable("KAFKA_BROKERS") ?? "kafka-host:9092";
var rabbitUrl = Environment.GetEnvironmentVariable("RABBITMQ_URL") ?? "amqp://guest:guest@rabbitmq-host:5672";

IProducer<Null, string>? kafkaProducer = null;
ConnectionMultiplexer? redisMux = null;

var app = builder.Build();

app.MapGet("/external/{id}", (string id) =>
    Results.Json(new { status = "ok", service = Service, endpoint = "external", id }));

app.MapGet("/error", () =>
    Results.Json(new { status = "error", service = Service, message = "Internal server error" }, statusCode: 500));

app.MapGet("/mysql", async () =>
{
    await using var conn = new MySqlConnection(
        $"Server={mysqlHost};Port={mysqlPort};User ID={mysqlUser};Password={mysqlPassword};Database={mysqlDatabase}");
    await conn.OpenAsync();
    await using var cmd = new MySqlCommand("SELECT NOW()", conn);
    var now = await cmd.ExecuteScalarAsync();
    return Results.Json(new { status = "ok", service = Service, endpoint = "mysql", result = now });
});

app.MapGet("/redis", async () =>
{
    redisMux ??= await ConnectionMultiplexer.ConnectAsync($"{redisHost}:{redisPort}");
    var db = redisMux.GetDatabase();
    await db.StringSetAsync("dotnet:sample", "hello-from-dotnet");
    var value = await db.StringGetAsync("dotnet:sample");
    return Results.Json(new { status = "ok", service = Service, endpoint = "redis", value = value.ToString() });
});

app.MapGet("/postgres", async () =>
{
    await using var conn = new NpgsqlConnection(
        $"Host={postgresHost};Port={postgresPort};Username={postgresUser};Password={postgresPassword};Database={postgresDatabase}");
    await conn.OpenAsync();
    await using var cmd = new NpgsqlCommand("SELECT NOW()", conn);
    var now = await cmd.ExecuteScalarAsync();
    return Results.Json(new { status = "ok", service = Service, endpoint = "postgres", result = now });
});

app.MapGet("/publish/kafka/{topic}/{text}", (string topic, string text) =>
{
    if (!topics.Contains(topic))
    {
        return Results.Json(new { status = "error", service = Service, message = $"Unknown topic: {topic}" }, statusCode: 400);
    }
    kafkaProducer ??= new ProducerBuilder<Null, string>(new ProducerConfig
    {
        BootstrapServers = kafkaBrokers,
        Acks = Acks.All,
    }).Build();
    kafkaProducer.Produce(topic, new Message<Null, string> { Value = text });
    kafkaProducer.Flush(TimeSpan.FromSeconds(10));
    return Results.Json(new { status = "ok", service = Service, broker = "kafka", topic, message = text });
});

app.MapGet("/publish/rabbit/{topic}/{text}", (string topic, string text) =>
{
    if (!topics.Contains(topic))
    {
        return Results.Json(new { status = "error", service = Service, message = $"Unknown topic: {topic}" }, statusCode: 400);
    }
    var factory = new ConnectionFactory { Uri = new Uri(rabbitUrl) };
    using var connection = factory.CreateConnection();
    using var channel = connection.CreateModel();
    channel.QueueDeclare(topic, durable: true, exclusive: false, autoDelete: false, arguments: null);
    var props = channel.CreateBasicProperties();
    props.Persistent = true;
    channel.BasicPublish("", topic, props, Encoding.UTF8.GetBytes(text));
    return Results.Json(new { status = "ok", service = Service, broker = "rabbit", topic, message = text });
});

app.MapGet("/call/all", async (IHttpClientFactory httpFactory) =>
{
    var results = new Dictionary<string, object>();
    foreach (var lang in peers.Keys)
    {
        results[lang] = await ProxyPayload(httpFactory, lang, "/external/all");
    }
    return Results.Json(new { status = "ok", from_service = Service, results });
});

app.MapGet("/{lang}/external/{id}", async (string lang, string id, IHttpClientFactory httpFactory) =>
    await Proxy(httpFactory, lang, $"/external/{id}"));
app.MapGet("/{lang}/error", async (string lang, IHttpClientFactory httpFactory) =>
    await Proxy(httpFactory, lang, "/error"));
app.MapGet("/{lang}/mysql", async (string lang, IHttpClientFactory httpFactory) =>
    await Proxy(httpFactory, lang, "/mysql"));
app.MapGet("/{lang}/redis", async (string lang, IHttpClientFactory httpFactory) =>
    await Proxy(httpFactory, lang, "/redis"));
app.MapGet("/{lang}/postgres", async (string lang, IHttpClientFactory httpFactory) =>
    await Proxy(httpFactory, lang, "/postgres"));
app.MapGet("/{lang}/publish/kafka/{topic}/{text}", async (string lang, string topic, string text, IHttpClientFactory httpFactory) =>
{
    if (!topics.Contains(topic))
    {
        return Results.Json(new { status = "error", service = Service, message = $"Unknown topic: {topic}" }, statusCode: 400);
    }
    return await Proxy(httpFactory, lang, $"/publish/kafka/{topic}/{text}");
});
app.MapGet("/{lang}/publish/rabbit/{topic}/{text}", async (string lang, string topic, string text, IHttpClientFactory httpFactory) =>
{
    if (!topics.Contains(topic))
    {
        return Results.Json(new { status = "error", service = Service, message = $"Unknown topic: {topic}" }, statusCode: 400);
    }
    return await Proxy(httpFactory, lang, $"/publish/rabbit/{topic}/{text}");
});

app.Run();

async Task<IResult> Proxy(IHttpClientFactory httpFactory, string lang, string path)
{
    if (!peers.ContainsKey(lang))
    {
        return Results.Json(new { status = "error", service = Service, message = $"Unknown language: {lang}" }, statusCode: 400);
    }
    try
    {
        return Results.Json(await ProxyPayload(httpFactory, lang, path));
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "error", from_service = Service, to = lang, message = ex.Message }, statusCode: 500);
    }
}

async Task<object> ProxyPayload(IHttpClientFactory httpFactory, string lang, string path)
{
    var client = httpFactory.CreateClient();
    client.Timeout = TimeSpan.FromSeconds(10);
    var resp = await client.GetAsync($"{peers[lang]}{path}");
    var body = await resp.Content.ReadAsStringAsync();
    return new { status = "ok", from_service = Service, to = lang, status_code = (int)resp.StatusCode, body };
}
