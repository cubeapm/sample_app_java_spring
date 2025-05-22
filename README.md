# Datadog Instrumentation

This branch contains code for Datadog instrumentation.

By default, hitting an API endpoint will generate a trace, which is sent to CubeAPM. This behavior is controlled via environment variables in [docker-compose.yml](docker-compose.yml).

Refer the project README below for more details.

## Troubleshooting

If the app does not show up in CubeAPM after integration is done, add the below environment variables to check Datadog tracer logs.

```shell
# Print Datadog tracer startup logs on screen
DD_TRACE_STARTUP_LOGS=true

# Enable Datadog tracer debug logging if needed to see detailed logs
#DD_TRACE_DEBUG=true
```

---

# Java Spring Boot Instrumentation

This is a sample app to demonstrate how to instrument Java Spring Boot app with **Datadog**, **Elastic**, **New Relic** and **OpenTelemetry**. It contains source code for the Spring Boot app which interacts with various services like Redis, MySQL, etc. to demonstrate tracing for these services. This repository has a docker compose file to set up all these services conveniently.

The code is organized into multiple branches. The main branch has the Spring Boot app without any instrumentation. Other branches then build upon the main branch to add specific instrumentations as below:

| Branch                                                                                         | Instrumentation | Code changes for instrumentation                                                                                |
| ---------------------------------------------------------------------------------------------- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| [main](https://github.com/cubeapm/sample_app_java_spring/tree/main)         | None            | -                                                                                                               |
| [datadog](https://github.com/cubeapm/sample_app_java_spring/tree/datadog) | Datadog       | [main...datadog](https://github.com/cubeapm/sample_app_java_spring/compare/main...datadog) |
| [elastic](https://github.com/cubeapm/sample_app_java_spring/tree/elastic) | Elastic       | [main...elastic](https://github.com/cubeapm/sample_app_java_spring/compare/main...elastic) |
| [newrelic](https://github.com/cubeapm/sample_app_java_spring/tree/newrelic) | New Relic       | [main...newrelic](https://github.com/cubeapm/sample_app_java_spring/compare/main...newrelic) |
| [otel](https://github.com/cubeapm/sample_app_java_spring/tree/otel)         | OpenTelemetry   | [main...otel](https://github.com/cubeapm/sample_app_java_spring/compare/main...otel)         |

# Setup

Clone this repository and go to the project directory. Then run the following commands

```
docker compose up --build
```

Spring Boot app will now be available at `http://localhost:8000`.

The app has various API endpoints to demonstrate integrations with Redis, MySQL, etc. Check out [src/main/java/sample_app_java_spring/sampleappjava/app.java](src/main/java/sample_app_java_spring/sampleappjava/app.java) for the list of API endpoints.

# Contributing

Please feel free to raise PR for any enhancements - additional service integrations, library version updates, documentation updates, etc.
