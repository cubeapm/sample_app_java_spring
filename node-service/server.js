const express = require("express");
const mysql = require("mysql2/promise");
const { Pool } = require("pg");
const Redis = require("ioredis");
const { Kafka } = require("kafkajs");
const amqp = require("amqplib");

const app = express();
const port = Number(process.env.PORT || 8001);
const SERVICE = "nodejs";
const TOPICS = new Set(["topic-1", "topic-2"]);
const PEERS = {
  java: process.env.JAVA_SERVICE_URL || "http://java-host:8000",
  python: process.env.PYTHON_SERVICE_URL || "http://python-host:8002",
  php: process.env.PHP_SERVICE_URL || "http://php-host:8003",
  dotnet: process.env.DOTNET_SERVICE_URL || "http://dotnet-host:8004",
};

const MYSQL_HOST = process.env.MYSQL_HOST || "mysql-host";
const MYSQL_PORT = Number(process.env.MYSQL_PORT || 3306);
const MYSQL_USER = process.env.MYSQL_USER || "root";
const MYSQL_PASSWORD = process.env.MYSQL_PASSWORD || "root";
const MYSQL_DATABASE = process.env.MYSQL_DATABASE || "test";
const POSTGRES_HOST = process.env.POSTGRES_HOST || "postgres-host";
const POSTGRES_PORT = Number(process.env.POSTGRES_PORT || 5432);
const POSTGRES_USER = process.env.POSTGRES_USER || "root";
const POSTGRES_PASSWORD = process.env.POSTGRES_PASSWORD || "root";
const POSTGRES_DATABASE = process.env.POSTGRES_DATABASE || "test";
const REDIS_HOST = process.env.REDIS_HOST || "redis-host";
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const KAFKA_BROKERS = (process.env.KAFKA_BROKERS || "kafka-host:9092").split(",");
const KAFKA_TOPICS = (process.env.KAFKA_TOPICS || "topic-1,topic-2").split(",");
const RABBITMQ_URL = process.env.RABBITMQ_URL || "amqp://guest:guest@rabbitmq-host:5672";
const RABBITMQ_QUEUES = (process.env.RABBITMQ_QUEUES || "topic-1,topic-2").split(",");

const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  maxRetriesPerRequest: 3,
});

const mysqlPool = mysql.createPool({
  host: MYSQL_HOST,
  port: MYSQL_PORT,
  user: MYSQL_USER,
  password: MYSQL_PASSWORD,
  database: MYSQL_DATABASE,
  waitForConnections: true,
  connectionLimit: 5,
});

const pgPool = new Pool({
  host: POSTGRES_HOST,
  port: POSTGRES_PORT,
  user: POSTGRES_USER,
  password: POSTGRES_PASSWORD,
  database: POSTGRES_DATABASE,
  max: 5,
});

let kafkaProducer = null;
let rabbitChannel = null;

function requireTopic(topic) {
  if (!TOPICS.has(topic)) {
    const err = new Error(`Unknown topic: ${topic}`);
    err.statusCode = 400;
    throw err;
  }
}

async function fetchJson(url) {
  const response = await fetch(url);
  const text = await response.text();
  return { status: response.status, body: text };
}

async function proxy(lang, path) {
  const base = PEERS[lang];
  if (!base) {
    const err = new Error(`Unknown language: ${lang}`);
    err.statusCode = 400;
    throw err;
  }
  try {
    const result = await fetchJson(`${base}${path}`);
    return { status: "ok", from: SERVICE, to: lang, status_code: result.status, body: result.body };
  } catch (err) {
    const error = new Error(err.message);
    error.statusCode = 500;
    throw error;
  }
}

function sendError(res, err) {
  const code = err.statusCode || 500;
  res.status(code).json({ status: "error", service: SERVICE, message: err.message });
}

app.get("/external/:id", (req, res) => {
  res.json({ status: "ok", service: SERVICE, endpoint: "external", id: req.params.id });
});

app.get("/error", (req, res) => {
  res.status(500).json({ status: "error", service: SERVICE, message: "Internal server error" });
});

app.get("/mysql", async (req, res) => {
  try {
    const [rows] = await mysqlPool.query("SELECT NOW() AS now_time");
    res.json({ status: "ok", service: SERVICE, endpoint: "mysql", result: rows[0] });
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/redis", async (req, res) => {
  try {
    await redis.set("nodejs:sample", "hello-from-nodejs");
    const value = await redis.get("nodejs:sample");
    res.json({ status: "ok", service: SERVICE, endpoint: "redis", value });
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/postgres", async (req, res) => {
  try {
    const result = await pgPool.query("SELECT NOW() AS now_time");
    res.json({ status: "ok", service: SERVICE, endpoint: "postgres", result: result.rows[0] });
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/publish/kafka/:topic/:text", async (req, res) => {
  try {
    requireTopic(req.params.topic);
    if (!kafkaProducer) {
      throw new Error("Kafka producer not ready");
    }
    await kafkaProducer.send({ topic: req.params.topic, messages: [{ value: req.params.text }] });
    res.json({
      status: "ok",
      service: SERVICE,
      broker: "kafka",
      topic: req.params.topic,
      message: req.params.text,
    });
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/publish/rabbit/:topic/:text", async (req, res) => {
  try {
    requireTopic(req.params.topic);
    if (!rabbitChannel) {
      throw new Error("RabbitMQ channel not ready");
    }
    await rabbitChannel.assertQueue(req.params.topic, { durable: true });
    rabbitChannel.sendToQueue(req.params.topic, Buffer.from(req.params.text), { persistent: true });
    res.json({
      status: "ok",
      service: SERVICE,
      broker: "rabbit",
      topic: req.params.topic,
      message: req.params.text,
    });
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/call/all", async (req, res) => {
  const results = {};
  for (const lang of Object.keys(PEERS)) {
    try {
      results[lang] = await proxy(lang, "/external/all");
    } catch (err) {
      results[lang] = { status: "error", message: err.message };
    }
  }
  res.json({ status: "ok", from: SERVICE, results });
});

app.get("/:lang/external/:id", async (req, res) => {
  try {
    res.json(await proxy(req.params.lang, `/external/${req.params.id}`));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/error", async (req, res) => {
  try {
    res.json(await proxy(req.params.lang, "/error"));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/mysql", async (req, res) => {
  try {
    res.json(await proxy(req.params.lang, "/mysql"));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/redis", async (req, res) => {
  try {
    res.json(await proxy(req.params.lang, "/redis"));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/postgres", async (req, res) => {
  try {
    res.json(await proxy(req.params.lang, "/postgres"));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/publish/kafka/:topic/:text", async (req, res) => {
  try {
    requireTopic(req.params.topic);
    res.json(await proxy(req.params.lang, `/publish/kafka/${req.params.topic}/${req.params.text}`));
  } catch (err) {
    sendError(res, err);
  }
});

app.get("/:lang/publish/rabbit/:topic/:text", async (req, res) => {
  try {
    requireTopic(req.params.topic);
    res.json(await proxy(req.params.lang, `/publish/rabbit/${req.params.topic}/${req.params.text}`));
  } catch (err) {
    sendError(res, err);
  }
});

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function startKafka() {
  const kafka = new Kafka({
    clientId: "cube-node-express",
    brokers: KAFKA_BROKERS,
    retry: { retries: 10 },
  });
  const producer = kafka.producer();
  const consumer = kafka.consumer({ groupId: "cube-node-express-dd-group" });

  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      await producer.connect();
      kafkaProducer = producer;
      await consumer.connect();
      for (const topic of KAFKA_TOPICS) {
        await consumer.subscribe({ topic, fromBeginning: false });
      }
      await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          console.log("Kafka message consumed:", {
            topic,
            partition,
            offset: message.offset,
            value: message.value ? message.value.toString() : null,
          });
        },
      });
      console.log(`Kafka producer+consumer ready on topics ${KAFKA_TOPICS.join(", ")}`);
      return;
    } catch (err) {
      console.error(`Kafka connect attempt ${attempt} failed:`, err.message);
      await sleep(2000);
    }
  }
  console.error("Kafka failed to start after retries");
}

async function startRabbit() {
  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      const connection = await amqp.connect(RABBITMQ_URL);
      const channel = await connection.createChannel();
      for (const queueName of RABBITMQ_QUEUES) {
        await channel.assertQueue(queueName, { durable: true });
        await channel.consume(queueName, async (msg) => {
          if (!msg) {
            return;
          }
          console.log("RabbitMQ message consumed:", {
            queue: queueName,
            value: msg.content.toString(),
          });
          channel.ack(msg);
        });
      }
      rabbitChannel = channel;
      console.log(`RabbitMQ producer+consumer ready on queues ${RABBITMQ_QUEUES.join(", ")}`);
      connection.on("error", (err) => console.error("RabbitMQ connection error:", err.message));
      return;
    } catch (err) {
      console.error(`RabbitMQ connect attempt ${attempt} failed:`, err.message);
      await sleep(2000);
    }
  }
  console.error("RabbitMQ failed to start after retries");
}

app.listen(port, () => {
  console.log(`Node.js Express (Datadog) service listening on port ${port}`);
  startKafka();
  startRabbit();
});
