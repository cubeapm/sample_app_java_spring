FROM ubuntu:22.04

WORKDIR /java

RUN apt-get update && apt-get install -y openjdk-17-jdk maven wget

COPY . .

RUN ./mvnw clean install  

EXPOSE 8000

CMD ["./mvnw", "spring-boot:run"]
