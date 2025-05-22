FROM ubuntu:20.04

WORKDIR /java

RUN apt-get update && apt-get install -y openjdk-17-jdk maven wget

COPY . .

ADD 'https://dtdg.co/latest-java-tracer' dd-java-agent.jar

RUN ./mvnw clean install  

EXPOSE 8000

CMD ["./mvnw", "spring-boot:run"]
