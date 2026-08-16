FROM ubuntu:22.04

WORKDIR /java

RUN apt-get update && apt-get install -y openjdk-17-jdk maven wget

COPY . .

# Use local jar from build context (download once: see comment below).
# Avoids Docker ADD timeouts on https://dtdg.co/latest-java-tracer -> GitHub.
# Download: curl -L -o dd-java-agent.jar https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/1.46.1/dd-java-agent-1.46.1.jar
RUN test -f dd-java-agent.jar || wget -O dd-java-agent.jar --timeout=60 --tries=5 \
      https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/1.46.1/dd-java-agent-1.46.1.jar

RUN ./mvnw clean install  

EXPOSE 8000

CMD ["./mvnw", "spring-boot:run"]
