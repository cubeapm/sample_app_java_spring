FROM ubuntu:22.04

WORKDIR /java

RUN apt-get update && apt-get install -y openjdk-17-jdk maven wget

COPY . .

RUN wget -O elastic-apm-agent.jar https://search.maven.org/remotecontent?filepath=co/elastic/apm/elastic-apm-agent/1.53.0/elastic-apm-agent-1.53.0.jar

RUN ./mvnw clean install  

EXPOSE 8000

CMD ["./mvnw", "spring-boot:run"]
