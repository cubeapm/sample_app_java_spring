package sample_app_java_spring.sampleappjava;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
public class app {

    private static final Logger logger = LoggerFactory.getLogger(app.class);

    @RequestMapping("/")
    public String index() {
        logger.info("Index endpoint called");
        return "Hello";
    }

    @RequestMapping("/exception")
    public String throwException() {
        logger.info("Exception occuerred");
        throw new RuntimeException("Exception");
    }

    @GetMapping("/param/{param}")
    public String getParam(@PathVariable String param) {
        logger.info("param called");
        return "Got param " + param;
    }
}
