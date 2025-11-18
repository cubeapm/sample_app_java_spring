package sample_app_java_spring.sampleappjava;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import com.newrelic.api.agent.Token;
import com.newrelic.api.agent.Trace;

@Service
public class EmailService {

    @Autowired
    private RestTemplate restTemplate;

    @Async("asyncExecutor")
    @Trace(async = true)
    public void sendEmail(String to, Token token) {
        token.link();
        System.out.println("Started sending email to: " + to 
            + " | Thread: " + Thread.currentThread().getName());

        try {
            Thread.sleep(5000); // simulate email sending delay
            String response = restTemplate.getForObject("http://localhost:8000/", String.class);
            System.out.println("API response: " + response);
        } catch (InterruptedException e) {
            e.printStackTrace();
        } catch (Exception e) {
            System.err.println("Error calling API: " + e.getMessage());
            e.printStackTrace();
        } finally {
            token.expire();
        }

        System.out.println("Finished sending email to: " + to);
    }
}
