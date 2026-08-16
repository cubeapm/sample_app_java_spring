import os

import pymysql
import psycopg2
import redis
import requests
from confluent_kafka import KafkaException, Producer
from flask import Flask, jsonify
from kombu import Connection, Queue
from werkzeug.exceptions import HTTPException

app = Flask(__name__)
app.url_map.strict_slashes = False

SERVICE = "python"
TOPICS = {"topic-1", "topic-2"}
PEERS = {
    "java": os.getenv("JAVA_SERVICE_URL", "http://java-host:8000"),
    "nodejs": os.getenv("NODE_SERVICE_URL", "http://node-host:8001"),
    "php": os.getenv("PHP_SERVICE_URL", "http://php-host:8003"),
    "dotnet": os.getenv("DOTNET_SERVICE_URL", "http://dotnet-host:8004"),
}

MYSQL_HOST = os.getenv("MYSQL_HOST", "mysql-host")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", "3306"))
MYSQL_USER = os.getenv("MYSQL_USER", "root")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "root")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "test")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres-host")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
POSTGRES_USER = os.getenv("POSTGRES_USER", "root")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "root")
POSTGRES_DATABASE = os.getenv("POSTGRES_DATABASE", "test")
REDIS_HOST = os.getenv("REDIS_HOST", "redis-host")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BROKERS = os.getenv("KAFKA_BROKERS", "kafka-host:9092").split(",")
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq-host:5672")

_kafka_producer = None
_redis = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def get_kafka_producer():
    global _kafka_producer
    if _kafka_producer is None:
        _kafka_producer = Producer(
            {
                "bootstrap.servers": ",".join(KAFKA_BROKERS),
                "acks": "all",
            }
        )
    return _kafka_producer


def require_topic(topic: str) -> None:
    if topic not in TOPICS:
        raise ValueError(f"Unknown topic: {topic}")


def proxy(lang: str, path: str):
    base = PEERS.get(lang)
    if not base:
        return jsonify(status="error", service=SERVICE, message=f"Unknown language: {lang}"), 400
    try:
        resp = requests.get(f"{base}{path}", timeout=10)
        return jsonify(
            status="ok",
            from_service=SERVICE,
            to=lang,
            status_code=resp.status_code,
            body=resp.text,
        ), 200
    except Exception as exc:  # noqa: BLE001
        return jsonify(status="error", from_service=SERVICE, to=lang, message=str(exc)), 500


@app.get("/external/<id>")
def external(id: str):
    return jsonify(status="ok", service=SERVICE, endpoint="external", id=id)


@app.get("/error")
def error():
    return jsonify(status="error", service=SERVICE, message="Internal server error"), 500


@app.get("/mysql")
def mysql():
    conn = pymysql.connect(
        host=MYSQL_HOST,
        port=MYSQL_PORT,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        database=MYSQL_DATABASE,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT NOW() AS now_time")
            row = cur.fetchone()
        return jsonify(status="ok", service=SERVICE, endpoint="mysql", result=row)
    finally:
        conn.close()


@app.get("/redis")
def redis_endpoint():
    _redis.set("python:sample", "hello-from-python")
    value = _redis.get("python:sample")
    return jsonify(status="ok", service=SERVICE, endpoint="redis", value=value)


@app.get("/postgres")
def postgres():
    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        dbname=POSTGRES_DATABASE,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT NOW() AS now_time")
            row = cur.fetchone()
        return jsonify(status="ok", service=SERVICE, endpoint="postgres", result={"now_time": str(row[0])})
    finally:
        conn.close()


@app.get("/publish/kafka/<topic>/<text>")
def publish_kafka(topic: str, text: str):
    require_topic(topic)
    producer = get_kafka_producer()
    producer.produce(topic, value=text.encode("utf-8"))
    remaining = producer.flush(10)
    if remaining:
        raise KafkaException(f"Kafka flush timed out with {remaining} message(s) still in queue")
    return jsonify(status="ok", service=SERVICE, broker="kafka", topic=topic, message=text)


@app.get("/publish/rabbit/<topic>/<text>")
def publish_rabbit(topic: str, text: str):
    require_topic(topic)
    queue = Queue(topic, durable=True)
    with Connection(RABBITMQ_URL) as conn:
        producer = conn.Producer()
        producer.publish(
            text,
            exchange="",
            routing_key=topic,
            declare=[queue],
            delivery_mode=2,
            serializer="json",
        )
    return jsonify(status="ok", service=SERVICE, broker="rabbit", topic=topic, message=text)


@app.get("/call/all")
def call_all():
    results = {}
    for lang in PEERS:
        body, _status = proxy(lang, "/external/all")
        results[lang] = body.get_json()
    return jsonify(status="ok", from_service=SERVICE, results=results)


@app.get("/<lang>/external/<id>")
def peer_external(lang: str, id: str):
    return proxy(lang, f"/external/{id}")


@app.get("/<lang>/error")
def peer_error(lang: str):
    return proxy(lang, "/error")


@app.get("/<lang>/mysql")
def peer_mysql(lang: str):
    return proxy(lang, "/mysql")


@app.get("/<lang>/redis")
def peer_redis(lang: str):
    return proxy(lang, "/redis")


@app.get("/<lang>/postgres")
def peer_postgres(lang: str):
    return proxy(lang, "/postgres")


@app.get("/<lang>/publish/kafka/<topic>/<text>")
def peer_kafka(lang: str, topic: str, text: str):
    require_topic(topic)
    return proxy(lang, f"/publish/kafka/{topic}/{text}")


@app.get("/<lang>/publish/rabbit/<topic>/<text>")
def peer_rabbit(lang: str, topic: str, text: str):
    require_topic(topic)
    return proxy(lang, f"/publish/rabbit/{topic}/{text}")


@app.errorhandler(ValueError)
def handle_value_error(err: ValueError):
    return jsonify(status="error", service=SERVICE, message=str(err)), 400


@app.errorhandler(Exception)
def handle_exception(err: Exception):
    if isinstance(err, HTTPException):
        return err
    return jsonify(status="error", service=SERVICE, message=str(err)), 500
