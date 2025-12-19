FROM ubuntu:22.04

ARG VERSION

WORKDIR /java

RUN apt-get update && apt-get install -y openjdk-17-jdk maven wget

COPY . .

ADD https://download.newrelic.com/newrelic/java-agent/newrelic-agent/${VERSION}/newrelic-agent-${VERSION}.jar newrelic-agent.jar

RUN ./mvnw clean install  

EXPOSE 8000

CMD ["./mvnw", "spring-boot:run"]
