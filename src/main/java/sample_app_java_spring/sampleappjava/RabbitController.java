package sample_app_java_spring.sampleappjava;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/rabbit")
public class RabbitController {

    private static final Logger LOGGER = LoggerFactory.getLogger(RabbitController.class);

    private final RabbitTopicService rabbitTopicService;

    public RabbitController(RabbitTopicService rabbitTopicService) {
        this.rabbitTopicService = rabbitTopicService;
    }

    @PostMapping("/publish")
    public ResponseEntity<Map<String, Object>> publishMessage(@RequestBody MessagePayload payload) {
        if (payload == null || !StringUtils.hasText(payload.message())) {
            return ResponseEntity.badRequest().body(Map.of(
                    "status", "error",
                    "message", "Message content must not be empty"
            ));
        }

        LOGGER.info("Received publish request: {}", payload.message());
        rabbitTopicService.publishMessage(payload);
        return ResponseEntity.ok(Map.of(
                "status", "sent",
                "message", payload.message()
        ));
    }

}

