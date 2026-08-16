package sample_app_java_spring.sampleappjava;

import org.springframework.amqp.core.Queue;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class MessagingConfig {

    @Value("${app.rabbitmq.queue1}")
    private String rabbitQueue1;

    @Value("${app.rabbitmq.queue2}")
    private String rabbitQueue2;

    @Bean
    public Queue sampleQueue1() {
        return new Queue(rabbitQueue1, true);
    }

    @Bean
    public Queue sampleQueue2() {
        return new Queue(rabbitQueue2, true);
    }
}
