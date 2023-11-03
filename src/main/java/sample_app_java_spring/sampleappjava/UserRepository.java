package sample_app_java_spring.sampleappjava;

import org.springframework.data.repository.CrudRepository;

public interface UserRepository extends CrudRepository<User , Integer>{
    
}
