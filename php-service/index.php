<?php
require_once __DIR__ . '/vendor/autoload.php';

use PhpAmqpLib\Connection\AMQPStreamConnection;
use PhpAmqpLib\Message\AMQPMessage;

header('Content-Type: application/json');

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
$path = rtrim($path, '/') ?: '/';

$service = 'php';
$topics = ['topic-1', 'topic-2'];
$peers = [
    'java' => getenv('JAVA_SERVICE_URL') ?: 'http://java-host:8000',
    'nodejs' => getenv('NODE_SERVICE_URL') ?: 'http://node-host:8001',
    'python' => getenv('PYTHON_SERVICE_URL') ?: 'http://python-host:8002',
    'dotnet' => getenv('DOTNET_SERVICE_URL') ?: 'http://dotnet-host:8004',
];

$mysqlHost = getenv('MYSQL_HOST') ?: 'mysql-host';
$mysqlPort = getenv('MYSQL_PORT') ?: '3306';
$mysqlUser = getenv('MYSQL_USER') ?: 'root';
$mysqlPassword = getenv('MYSQL_PASSWORD') ?: 'root';
$mysqlDatabase = getenv('MYSQL_DATABASE') ?: 'test';
$postgresHost = getenv('POSTGRES_HOST') ?: 'postgres-host';
$postgresPort = getenv('POSTGRES_PORT') ?: '5432';
$postgresUser = getenv('POSTGRES_USER') ?: 'root';
$postgresPassword = getenv('POSTGRES_PASSWORD') ?: 'root';
$postgresDatabase = getenv('POSTGRES_DATABASE') ?: 'test';
$redisHost = getenv('REDIS_HOST') ?: 'redis-host';
$redisPort = (int) (getenv('REDIS_PORT') ?: 6379);
$kafkaBrokers = getenv('KAFKA_BROKERS') ?: 'kafka-host:9092';
$rabbitUrl = getenv('RABBITMQ_URL') ?: 'amqp://guest:guest@rabbitmq-host:5672';

function json_out(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
}

function require_topic(string $topic, array $topics, string $service): void
{
    if (!in_array($topic, $topics, true)) {
        json_out(400, ['status' => 'error', 'service' => $service, 'message' => "Unknown topic: {$topic}"]);
        exit;
    }
}

function http_get(string $url): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_FOLLOWLOCATION => true,
    ]);
    $body = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($body === false) {
        return [500, null, $error ?: 'curl request failed'];
    }
    return [$status > 0 ? $status : 500, $body, null];
}

function proxy(string $lang, string $path, array $peers, string $service): void
{
    if (!isset($peers[$lang])) {
        json_out(400, ['status' => 'error', 'service' => $service, 'message' => "Unknown language: {$lang}"]);
        return;
    }
    [$status, $body, $error] = http_get(rtrim($peers[$lang], '/') . $path);
    if ($error !== null) {
        json_out(500, [
            'status' => 'error',
            'from' => $service,
            'to' => $lang,
            'message' => $error,
        ]);
        return;
    }
    json_out(200, [
        'status' => 'ok',
        'from' => $service,
        'to' => $lang,
        'status_code' => $status,
        'body' => $body,
    ]);
}

function publish_kafka(string $brokers, string $topic, string $message): void
{
    if (!extension_loaded('rdkafka')) {
        throw new RuntimeException('ext-rdkafka is required for Datadog Kafka instrumentation');
    }

    $conf = new RdKafka\Conf();
    $conf->set('metadata.broker.list', $brokers);
    $conf->set('socket.timeout.ms', '10000');
    $conf->set('message.timeout.ms', '10000');

    $producer = new RdKafka\Producer($conf);
    $rdTopic = $producer->newTopic($topic);
    $rdTopic->producev(RD_KAFKA_PARTITION_UA, 0, $message);
    $producer->poll(0);

    $result = $producer->flush(10000);
    if ($result !== RD_KAFKA_RESP_ERR_NO_ERROR) {
        throw new RuntimeException('Kafka flush failed with code ' . $result);
    }
}

function publish_rabbit(string $amqpUrl, string $queue, string $message): void
{
    $parts = parse_url($amqpUrl);
    $connection = new AMQPStreamConnection(
        $parts['host'] ?? 'rabbitmq-host',
        $parts['port'] ?? 5672,
        $parts['user'] ?? 'guest',
        $parts['pass'] ?? 'guest',
        isset($parts['path']) ? ltrim($parts['path'], '/') ?: '/' : '/'
    );
    $channel = $connection->channel();
    $channel->queue_declare($queue, false, true, false, false);
    $channel->basic_publish(new AMQPMessage($message, ['delivery_mode' => 2]), '', $queue);
    $channel->close();
    $connection->close();
}

try {
    if (preg_match('#^/external/([^/]+)$#', $path, $m)) {
        json_out(200, ['status' => 'ok', 'service' => $service, 'endpoint' => 'external', 'id' => $m[1]]);
    } elseif ($path === '/error') {
        json_out(500, ['status' => 'error', 'service' => $service, 'message' => 'Internal server error']);
    } elseif ($path === '/mysql') {
        $pdo = new PDO(
            "mysql:host={$mysqlHost};port={$mysqlPort};dbname={$mysqlDatabase}",
            $mysqlUser,
            $mysqlPassword,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );
        $now = $pdo->query('SELECT NOW()')->fetchColumn();
        json_out(200, ['status' => 'ok', 'service' => $service, 'endpoint' => 'mysql', 'result' => $now]);
    } elseif ($path === '/redis') {
        $redis = new Redis();
        $redis->connect($redisHost, $redisPort, 3.0);
        $redis->set('php:sample', 'hello-from-php');
        json_out(200, [
            'status' => 'ok',
            'service' => $service,
            'endpoint' => 'redis',
            'value' => $redis->get('php:sample'),
        ]);
    } elseif ($path === '/postgres') {
        $pdo = new PDO(
            "pgsql:host={$postgresHost};port={$postgresPort};dbname={$postgresDatabase}",
            $postgresUser,
            $postgresPassword,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );
        $now = $pdo->query('SELECT NOW()')->fetchColumn();
        json_out(200, ['status' => 'ok', 'service' => $service, 'endpoint' => 'postgres', 'result' => $now]);
    } elseif (preg_match('#^/publish/kafka/([^/]+)/([^/]+)$#', $path, $m)) {
        require_topic($m[1], $topics, $service);
        publish_kafka($kafkaBrokers, $m[1], $m[2]);
        json_out(200, [
            'status' => 'ok',
            'service' => $service,
            'broker' => 'kafka',
            'topic' => $m[1],
            'message' => $m[2],
        ]);
    } elseif (preg_match('#^/publish/rabbit/([^/]+)/([^/]+)$#', $path, $m)) {
        require_topic($m[1], $topics, $service);
        publish_rabbit($rabbitUrl, $m[1], $m[2]);
        json_out(200, [
            'status' => 'ok',
            'service' => $service,
            'broker' => 'rabbit',
            'topic' => $m[1],
            'message' => $m[2],
        ]);
    } elseif ($path === '/call/all') {
        $results = [];
        foreach ($peers as $lang => $base) {
            [$status, $body, $error] = http_get(rtrim($base, '/') . '/external/all');
            if ($error !== null) {
                $results[$lang] = ['status' => 'error', 'message' => $error];
            } else {
                $results[$lang] = [
                    'status' => 'ok',
                    'from' => $service,
                    'to' => $lang,
                    'status_code' => $status,
                    'body' => $body,
                ];
            }
        }
        json_out(200, ['status' => 'ok', 'from' => $service, 'results' => $results]);
    } elseif (preg_match('#^/([^/]+)/external/([^/]+)$#', $path, $m)) {
        proxy($m[1], '/external/' . $m[2], $peers, $service);
    } elseif (preg_match('#^/([^/]+)/error$#', $path, $m)) {
        proxy($m[1], '/error', $peers, $service);
    } elseif (preg_match('#^/([^/]+)/mysql$#', $path, $m)) {
        proxy($m[1], '/mysql', $peers, $service);
    } elseif (preg_match('#^/([^/]+)/redis$#', $path, $m)) {
        proxy($m[1], '/redis', $peers, $service);
    } elseif (preg_match('#^/([^/]+)/postgres$#', $path, $m)) {
        proxy($m[1], '/postgres', $peers, $service);
    } elseif (preg_match('#^/([^/]+)/publish/kafka/([^/]+)/([^/]+)$#', $path, $m)) {
        require_topic($m[2], $topics, $service);
        proxy($m[1], '/publish/kafka/' . $m[2] . '/' . $m[3], $peers, $service);
    } elseif (preg_match('#^/([^/]+)/publish/rabbit/([^/]+)/([^/]+)$#', $path, $m)) {
        require_topic($m[2], $topics, $service);
        proxy($m[1], '/publish/rabbit/' . $m[2] . '/' . $m[3], $peers, $service);
    } else {
        json_out(404, ['status' => 'error', 'message' => 'Not found', 'path' => $path]);
    }
} catch (Throwable $e) {
    json_out(500, ['status' => 'error', 'service' => $service, 'message' => $e->getMessage()]);
}
