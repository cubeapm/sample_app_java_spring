package sample_app_java_spring.sampleappjava;

// import org.apache.kafka.clients.producer.Producer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;
import org.springframework.cache.annotation.Cacheable;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
public class app {

    private static final Logger logger = LoggerFactory.getLogger(app.class);

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RestTemplate restTemplate;


    @RequestMapping("/")
    public String index(){
        logger.info("Index endpoint called");
        return "Hello";
    }

    @RequestMapping("/exception")
    public String throwException() {
        logger.info("GET /exception called");
        throw new RuntimeException("Exception");
        }

    @GetMapping("/param/{param}")
    public String getParam(@PathVariable String param) {
        logger.info("GET /param/{} called", param);
        return "Got param " + param;
    }

    @GetMapping("/api")
    public String api() {
        logger.info("GET /api called – calling external service");
        String response = restTemplate.getForObject("http://localhost:8000", String.class);
        logger.info("GET /api response received");
        return "API called: " + response;
    }

    // curl http://localhost:8080/mysql/add -d name="xyz" -d email="xyz@gmail.com"
    @PostMapping("/mysql/add")
    public @ResponseBody User addNewUser(@RequestParam String name , @RequestParam String email) {
        logger.info("POST /mysql/add called with name={}, email={}", name, email);
        User springUser = new User();
        springUser.setName(name);
        springUser.setEmail(email);
        userRepository.save(springUser);
        logger.info("User saved successfully with id={}", springUser.getId());
        return springUser;
    }

    // get all the added values above(using sql database)
    // curl http://localhost:8080/all
    @GetMapping("/all")
    public @ResponseBody Iterable<User> getAllUsers() {
        logger.info("GET /all called");
        return userRepository.findAll();
    }


    @GetMapping("/redis")
    @Cacheable("redisCache")
    public String getCachedRedisMessage() {
        logger.info("GET /redis called");
        return "Redis called";
    }
}
