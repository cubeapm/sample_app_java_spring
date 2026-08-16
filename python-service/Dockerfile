FROM python:3.12-slim

WORKDIR /app

# confluent-kafka may need librdkafka on some platforms
RUN apt-get update \
    && apt-get install -y --no-install-recommends librdkafka1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8002

CMD ["ddtrace-run", "gunicorn", "-b", "0.0.0.0:8002", "app:app"]
