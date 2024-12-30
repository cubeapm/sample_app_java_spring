FROM ubuntu:20.04

WORKDIR /java

RUN apt-get update && apt-get install -y \
    openjdk-17-jdk \
    maven \
    wget

COPY . .

ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar .

ENV JAVA_TOOL_OPTIONS "-javaagent:./opentelemetry-javaagent.jar"

RUN ./mvnw clean install  

EXPOSE 8081

CMD ["./mvnw", "spring-boot:run"]
