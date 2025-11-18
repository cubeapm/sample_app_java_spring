package sample_app_java_spring.sampleappjava;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import com.newrelic.api.agent.Trace;

@Service
public class RabbitTopicService {

    private static final Logger LOGGER = LoggerFactory.getLogger(RabbitTopicService.class);

    private final RabbitTemplate rabbitTemplate;
    private final String exchangeName;
    private final String routingKey;
    
    @Autowired
    private RestTemplate restTemplate;

    @Autowired
    private UserRepository userRepository;

    public RabbitTopicService(RabbitTemplate rabbitTemplate,
                              @Value("${rabbitmq.exchange}") String exchangeName,
                              @Value("${rabbitmq.routing-key}") String routingKey) {
        this.rabbitTemplate = rabbitTemplate;
        this.exchangeName = exchangeName;
        this.routingKey = routingKey;
    }

    @Trace(dispatcher = true)
    public void publishMessage(MessagePayload payload) {
        LOGGER.info("Publishing message to exchange '{}' with routing key '{}': {}", exchangeName, routingKey, payload);
        rabbitTemplate.convertAndSend(exchangeName, routingKey, payload);
    }

    @Trace(dispatcher = true)
    @RabbitListener(queues = "${rabbitmq.queue}")
    public void listen(MessagePayload payload) {
        LOGGER.info("Consumed message from queue: {}", payload.message());
        try {
            // we need to make a db call here
            User springUser = new User();
            springUser.setName("xyz");
            springUser.setEmail("xyz@gmail.com");
            userRepository.save(springUser);
            LOGGER.info("User saved to database: {}", springUser);
            String response = restTemplate.getForObject("http://localhost:8000/", String.class);
            LOGGER.info("API response from consumer: {}", response);
        } catch (Exception e) {
            LOGGER.error("Error calling API from consumer: {}", e.getMessage());
        }
    }
}

