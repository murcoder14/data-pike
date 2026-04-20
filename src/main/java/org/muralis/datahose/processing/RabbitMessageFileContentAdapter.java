package org.muralis.datahose.processing;

import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.util.Collector;
import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Adapts a RabbitMQ stream payload into S3FileContent so the existing
 * FileProcessor path can be reused in local mode without S3 access.
 */
public class RabbitMessageFileContentAdapter extends RichFlatMapFunction<String, S3FileContent> {

    private static final Logger LOG = LoggerFactory.getLogger(RabbitMessageFileContentAdapter.class);

    private final String streamName;
    private final AtomicLong sequence = new AtomicLong();

    public RabbitMessageFileContentAdapter(String streamName) {
        this.streamName = streamName;
    }

    @Override
    public void flatMap(String payload, Collector<S3FileContent> out) {
        if (payload == null || payload.isBlank()) {
            return;
        }

        byte[] content = payload.getBytes(StandardCharsets.UTF_8);
        long id = sequence.incrementAndGet();

        S3Notification syntheticNotification = new S3Notification(
                "rabbitmq://" + streamName,
            "message-" + id + ".payload",
                Instant.now().toString(),
                "rabbitmq-streams");

        FileFormat detectedFormat = FileFormatDetector.detect(syntheticNotification, content);
        if (detectedFormat == FileFormat.UNKNOWN) {
            LOG.warn("Dropping RabbitMQ payload {} because format could not be detected", id);
            return;
        }

        out.collect(new S3FileContent(syntheticNotification, content, detectedFormat));
    }
}
