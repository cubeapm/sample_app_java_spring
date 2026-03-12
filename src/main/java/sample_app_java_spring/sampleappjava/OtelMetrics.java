package sample_app_java_spring.sampleappjava;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Duration;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.exporter.logging.LoggingMetricExporter;
import io.opentelemetry.exporter.otlp.http.metrics.OtlpHttpMetricExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.export.PeriodicMetricReader;
import io.opentelemetry.sdk.resources.Resource;

public class OtelMetrics {
    private static Meter meter;

    public static synchronized void init() {
        if (meter != null) {
            return;
        }

        String hostName = "UNSET";
        try {
            hostName = InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
        }

        Resource resource = Resource.getDefault().merge(
                Resource.builder()
                        .put("service.name", System.getenv("ELASTIC_APM_SERVICE_NAME"))
                        // .put("service.version", serviceVersion)
                        .put("host.name", hostName)
                        .put("process.pid", ProcessHandle.current().pid())
                        .build());

        OtlpHttpMetricExporter exporter = OtlpHttpMetricExporter.builder()
                .setEndpoint(System.getenv("ELASTIC_APM_SERVER_URL") + "/api/metrics/v1/save/otlp")
                .build();
        /*
         * LoggingMetricExporter can be used in place of OtlpHttpMetricExporter
         * for testing. It will put the metrics data in logs.
         */
        // LoggingMetricExporter exporter = LoggingMetricExporter.create();

        PeriodicMetricReader reader = PeriodicMetricReader.builder(exporter)
                .setInterval(Duration.ofSeconds(60))
                .build();

        SdkMeterProvider meterProvider = SdkMeterProvider.builder()
                .setResource(resource)
                .registerMetricReader(reader)
                .build();

        OpenTelemetry openTelemetry = OpenTelemetrySdk.builder()
                .setMeterProvider(meterProvider)
                .build();

        /*
         * Elastic APM agent sets GlobalOpenTelemetry with its OTel Bridge,
         * and GlobalOpenTelemetry.set() throws exception if called again,
         * so we don't set GlobalOpenTelemetry here.
         */
        // GlobalOpenTelemetry.set(openTelemetry);

        meter = openTelemetry.getMeter("custom-metrics");
    }

    public static Meter meter() {
        if (meter == null) {
            throw new IllegalStateException("OtelMetrics.init() not called");
        }
        return meter;
    }
}