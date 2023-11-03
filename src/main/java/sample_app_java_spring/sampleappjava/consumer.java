package sample_app_java_spring.sampleappjava;

import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Service

public class consumer {


    @KafkaListener(topics = "codeDecode_Topic" , groupId = "codeDecode_group")
    public void listenToTopic(String receivedMessage) {
        System.out.println("The message received is " + receivedMessage);
    }
    
}
