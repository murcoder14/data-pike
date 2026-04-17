package org.muralis.datahose.source;

import com.rabbitmq.stream.Consumer;
import com.rabbitmq.stream.ConsumerBuilder;
import com.rabbitmq.stream.Environment;
import com.rabbitmq.stream.OffsetSpecification;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.streaming.api.functions.source.legacy.RichParallelSourceFunction;
import org.apache.flink.streaming.api.functions.source.legacy.SourceFunction;
import org.muralis.datahose.configuration.AppConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * Flink source function backed by RabbitMQ Streams Java client.
 */
public class RabbitMqStreamsSourceFunction extends RichParallelSourceFunction<String> {

    private static final Logger LOG = LoggerFactory.getLogger(RabbitMqStreamsSourceFunction.class);

    private final AppConfig.RabbitMqConfig config;

    private transient volatile boolean running;
    private transient Environment environment;
    private transient Consumer consumer;
    private transient BlockingQueue<String> queue;

    public RabbitMqStreamsSourceFunction(AppConfig.RabbitMqConfig config) {
        this.config = config;
    }

    @Override
    public void open(OpenContext openContext) {
        this.running = true;
        this.queue = new LinkedBlockingQueue<>();

        this.environment = Environment.builder()
                .host(config.host())
                .port(config.port())
                .username(config.username())
                .password(config.password())
                .virtualHost(config.virtualHost())
                .build();

        try {
            environment.streamCreator().stream(config.streamName()).create();
            LOG.info("Created RabbitMQ stream '{}'", config.streamName());
        } catch (Exception e) {
            LOG.debug("RabbitMQ stream '{}' may already exist: {}", config.streamName(), e.getMessage());
        }

        ConsumerBuilder builder = environment.consumerBuilder()
                .stream(config.streamName())
            .name(config.consumerName())
                .offset(OffsetSpecification.next())
                .messageHandler((context, message) -> {
                    if (!running) {
                        return;
                    }
                    String payload = new String(message.getBodyAsBinary(), StandardCharsets.UTF_8);
                try {
                queue.put(payload);
                } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                LOG.warn("Interrupted while buffering RabbitMQ payload from stream '{}'", config.streamName());
                    }
            });

        builder.autoTrackingStrategy()
            .messageCountBeforeStorage(1)
            .builder();

        this.consumer = builder.build();

        LOG.info("RabbitMQ Streams source started: host={}, port={}, vhost={}, stream={}, consumerName={}",
            config.host(), config.port(), config.virtualHost(), config.streamName(), config.consumerName());
    }

    @Override
    public void run(SourceFunction.SourceContext<String> ctx) throws Exception {
        while (running) {
            String payload = queue.poll(config.pollTimeoutMs(), TimeUnit.MILLISECONDS);
            if (payload == null) {
                continue;
            }
            synchronized (ctx.getCheckpointLock()) {
                ctx.collect(payload);
            }
        }
    }

    @Override
    public void cancel() {
        running = false;
        closeResources();
    }

    @Override
    public void close() {
        running = false;
        closeResources();
    }

    private void closeResources() {
        if (consumer != null) {
            try {
                consumer.close();
            } catch (Exception e) {
                LOG.warn("Failed to close RabbitMQ consumer", e);
            }
            consumer = null;
        }

        if (environment != null) {
            try {
                environment.close();
            } catch (Exception e) {
                LOG.warn("Failed to close RabbitMQ environment", e);
            }
            environment = null;
        }
    }
}
