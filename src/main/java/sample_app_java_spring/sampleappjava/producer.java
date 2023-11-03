package sample_app_java_spring.sampleappjava;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

@Service
public class producer {

    @Autowired
    KafkaTemplate<String, String> kafkaTemplate;

    public void sendMsgToTopic(String message) {
        kafkaTemplate.send("codeDecode_Topic",message);
    }
    
}
