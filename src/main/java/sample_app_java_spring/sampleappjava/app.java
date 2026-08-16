package sample_app_java_spring.sampleappjava;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.RestTemplate;

@RestController
public class app {

    private static final Logger logger = LoggerFactory.getLogger(app.class);
    private static final Set<String> PEERS = Set.of("nodejs", "python", "php", "dotnet");
    private static final Set<String> TOPICS = Set.of("topic-1", "topic-2");

    private final JdbcTemplate mysqlJdbcTemplate;
    private final JdbcTemplate postgresJdbcTemplate;
    private final StringRedisTemplate redis;
    private final RestTemplate restTemplate;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final RabbitTemplate rabbitTemplate;

    @Value("${node.service.url}")
    private String nodeServiceUrl;
    @Value("${python.service.url}")
    private String pythonServiceUrl;
    @Value("${php.service.url}")
    private String phpServiceUrl;
    @Value("${dotnet.service.url}")
    private String dotnetServiceUrl;

    public app(
            @Qualifier("jdbcTemplate") JdbcTemplate mysqlJdbcTemplate,
            @Qualifier("postgresJdbcTemplate") JdbcTemplate postgresJdbcTemplate,
            StringRedisTemplate redis,
            RestTemplate restTemplate,
            KafkaTemplate<String, String> kafkaTemplate,
            RabbitTemplate rabbitTemplate) {
        this.mysqlJdbcTemplate = mysqlJdbcTemplate;
        this.postgresJdbcTemplate = postgresJdbcTemplate;
        this.redis = redis;
        this.restTemplate = restTemplate;
        this.kafkaTemplate = kafkaTemplate;
        this.rabbitTemplate = rabbitTemplate;
    }

    @GetMapping("/external/{id}")
    public Map<String, Object> external(@PathVariable String id) {
        return json("status", "ok", "service", "java", "endpoint", "external", "id", id);
    }

    @GetMapping("/error")
    public ResponseEntity<Map<String, Object>> error() {
        return ResponseEntity.status(500).body(json("status", "error", "service", "java", "message", "Internal server error"));
    }

    @GetMapping("/mysql")
    public Map<String, Object> mysql() {
        Object now = mysqlJdbcTemplate.queryForObject("SELECT NOW()", Object.class);
        return json("status", "ok", "service", "java", "endpoint", "mysql", "result", now);
    }

    @GetMapping("/redis")
    public Map<String, Object> redis() {
        redis.opsForValue().set("java:sample", "hello-from-java");
        return json("status", "ok", "service", "java", "endpoint", "redis", "value", redis.opsForValue().get("java:sample"));
    }

    @GetMapping("/postgres")
    public Map<String, Object> postgres() {
        Object now = postgresJdbcTemplate.queryForObject("SELECT NOW()", Object.class);
        return json("status", "ok", "service", "java", "endpoint", "postgres", "result", now);
    }

    @GetMapping("/publish/kafka/{topic}/{text}")
    public Map<String, Object> publishKafka(@PathVariable String topic, @PathVariable String text) {
        requireTopic(topic);
        kafkaTemplate.send(topic, text);
        return json("status", "ok", "service", "java", "broker", "kafka", "topic", topic, "message", text);
    }

    @GetMapping("/publish/rabbit/{topic}/{text}")
    public Map<String, Object> publishRabbit(@PathVariable String topic, @PathVariable String text) {
        requireTopic(topic);
        rabbitTemplate.convertAndSend(topic, text);
        return json("status", "ok", "service", "java", "broker", "rabbit", "topic", topic, "message", text);
    }

    @GetMapping("/call/all")
    public Map<String, Object> callAll() {
        Map<String, Object> results = new LinkedHashMap<>();
        for (String peer : PEERS) {
            results.put(peer, proxy(peer, "/external/all"));
        }
        return json("status", "ok", "from", "java", "results", results);
    }

    @GetMapping("/{lang}/external/{id}")
    public Map<String, Object> peerExternal(@PathVariable String lang, @PathVariable String id) {
        return proxy(lang, "/external/" + id);
    }

    @GetMapping("/{lang}/error")
    public Map<String, Object> peerError(@PathVariable String lang) {
        return proxy(lang, "/error");
    }

    @GetMapping("/{lang}/mysql")
    public Map<String, Object> peerMysql(@PathVariable String lang) {
        return proxy(lang, "/mysql");
    }

    @GetMapping("/{lang}/redis")
    public Map<String, Object> peerRedis(@PathVariable String lang) {
        return proxy(lang, "/redis");
    }

    @GetMapping("/{lang}/postgres")
    public Map<String, Object> peerPostgres(@PathVariable String lang) {
        return proxy(lang, "/postgres");
    }

    @GetMapping("/{lang}/publish/kafka/{topic}/{text}")
    public Map<String, Object> peerKafka(@PathVariable String lang, @PathVariable String topic, @PathVariable String text) {
        requireTopic(topic);
        return proxy(lang, "/publish/kafka/" + topic + "/" + text);
    }

    @GetMapping("/{lang}/publish/rabbit/{topic}/{text}")
    public Map<String, Object> peerRabbit(@PathVariable String lang, @PathVariable String topic, @PathVariable String text) {
        requireTopic(topic);
        return proxy(lang, "/publish/rabbit/" + topic + "/" + text);
    }

    private Map<String, Object> proxy(String lang, String path) {
        if (!PEERS.contains(lang)) {
            throw new IllegalArgumentException("Unknown language: " + lang);
        }
        String url = peerUrl(lang) + path;
        logger.info("Proxy java -> {} {}", lang, path);
        try {
            ResponseEntity<String> resp = restTemplate.getForEntity(url, String.class);
            return json("status", "ok", "from", "java", "to", lang, "status_code", resp.getStatusCode().value(), "body", resp.getBody());
        } catch (HttpStatusCodeException ex) {
            return json("status", "ok", "from", "java", "to", lang, "status_code", ex.getStatusCode().value(), "body", ex.getResponseBodyAsString());
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to reach " + lang + ": " + ex.getMessage(), ex);
        }
    }

    private String peerUrl(String lang) {
        switch (lang) {
            case "nodejs":
                return nodeServiceUrl;
            case "python":
                return pythonServiceUrl;
            case "php":
                return phpServiceUrl;
            case "dotnet":
                return dotnetServiceUrl;
            default:
                throw new IllegalArgumentException("Unknown language: " + lang);
        }
    }

    private void requireTopic(String topic) {
        if (!TOPICS.contains(topic)) {
            throw new IllegalArgumentException("Unknown topic: " + topic);
        }
    }

    private Map<String, Object> json(Object... kv) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            map.put(String.valueOf(kv[i]), kv[i + 1]);
        }
        return map;
    }
}
