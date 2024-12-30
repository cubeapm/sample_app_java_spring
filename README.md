# Java Spring Boot OpenTelemetry Instrumentation

This is a sample app to demonstrate how to instrument Java Spring Boot app with OpenTelemetry. It contains source code for the Spring Boot app which interacts with various services like Redis, MySQL, etc. to demonstrate tracing for these services. This repository has a docker compose file to set up all these services conveniently.

This repository is inentionally designed to work with any OpenTelemetry backend, not just CubeAPM. In fact, it can even work without any OpenTelemetry backend (by dumping traces to console, which is also the default behaviour).

## Setup

Clone this repository and go to the project directory. Then run the following commands

```
docker compose up --build
```

Flask app will now be available at `http://localhost:8081`.

Open http://localhost:8081 in your browser and refresh the page a few times to generate some traces. Traces are printed to console (where docker compose is running) by default. If you want to send traces to a backend tool, comment out the `OTEL_TRACES_EXPORTER=console` line and uncomment the `OTEL_TRACES_EXPORTER=otlp` and `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=...` line in [docker-compose.yml](docker-compose.yml).


## Contributing

Please feel free to raise PR for any enhancements - additional service integrations, library version updates, documentation updates, etc.
