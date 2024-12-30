package sample_app_java_spring.sampleappjava;

// import org.apache.kafka.clients.producer.Producer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.cache.annotation.Cacheable;

@RestController
public class app {

    @Autowired
    private UserRepository userRepository;



    @RequestMapping("/")
    public String index(){
        return "Hello";
    }

    @RequestMapping("/exception")
    public String throwException() {
        throw new RuntimeException("Exception");
        }

    // curl http://localhost:8080/mysql/add -d name="xyz" -d email="xyz@gmail.com"
    @PostMapping("/mysql/add")
    public @ResponseBody User addNewUser(@RequestParam String name , @RequestParam String email) {
        User springUser = new User();
        springUser.setName(name);
        springUser.setEmail(email);
        userRepository.save(springUser);
        return springUser;
    }

    // get all the added values above(using sql database)
    // curl http://localhost:8080/all
    @GetMapping("/all")
    public @ResponseBody Iterable<User> getAllUsers() {
        return userRepository.findAll();
    }


    @GetMapping("/redis")
    @Cacheable("redisCache")
    public String getCachedRedisMessage() {
        return "redis called";
    }
}
