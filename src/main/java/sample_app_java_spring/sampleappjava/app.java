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

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RestTemplate restTemplate;

    private static final Logger logger = LoggerFactory.getLogger(app.class);


    @RequestMapping("/")
    public String index(){
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

    @GetMapping("/api")
    public String api() {
        logger.info("api called calling external service");
        String response = restTemplate.getForObject("http://java2:8001", String.class);
        logger.info("api response received");
        return "API called: " + response;
    }

    // curl http://localhost:8080/mysql/add -d name="xyz" -d email="xyz@gmail.com"
    @PostMapping("/mysql/add")
    public @ResponseBody User addNewUser(@RequestParam String name , @RequestParam String email) {
        logger.info("mysql called to add user");
        User springUser = new User();
        springUser.setName(name);
        springUser.setEmail(email);
        userRepository.save(springUser);
        logger.info("User saved successfully");
        return springUser;
    }

    // get all the added values above(using sql database)
    // curl http://localhost:8080/all
    @GetMapping("/all")
    public @ResponseBody Iterable<User> getAllUsers() {
        logger.info("all users called");
        return userRepository.findAll();
    }


    @GetMapping("/redis")
    @Cacheable("redisCache")
    public String getCachedRedisMessage() {
        logger.info("redis called");
        return "Redis called";
    }
}
