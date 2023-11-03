package sample_app_java_spring.sampleappjava;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

@SpringBootApplication
@EnableCaching

public class SampleAppJavaApplication {

	public static void main(String[] args) {
		SpringApplication.run(SampleAppJavaApplication.class, args);
	}

}
