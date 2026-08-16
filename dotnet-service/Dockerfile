FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY DotnetService.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app

ARG TRACER_VERSION=3.49.0
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && mkdir -p /opt/datadog \
    && if [ "$TARGETARCH" = "arm64" ]; then ARCH_SUFFIX=".arm64"; else ARCH_SUFFIX=""; fi \
    && curl -fsSL -o /tmp/datadog-dotnet-apm.tar.gz \
         "https://github.com/DataDog/dd-trace-dotnet/releases/download/v${TRACER_VERSION}/datadog-dotnet-apm-${TRACER_VERSION}${ARCH_SUFFIX}.tar.gz" \
    && tar -C /opt/datadog -xzf /tmp/datadog-dotnet-apm.tar.gz \
    && rm /tmp/datadog-dotnet-apm.tar.gz \
    && /opt/datadog/createLogPath.sh \
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

ENV CORECLR_ENABLE_PROFILING=1
ENV CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8}
ENV CORECLR_PROFILER_PATH=/opt/datadog/Datadog.Trace.ClrProfiler.Native.so
ENV DD_DOTNET_TRACER_HOME=/opt/datadog
ENV ASPNETCORE_URLS=http://0.0.0.0:8004

COPY --from=build /app .
EXPOSE 8004
ENTRYPOINT ["dotnet", "DotnetService.dll"]
