package org.muralis.datahose.processing;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.muralis.datahose.model.S3Notification;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.metrics.Counter;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.Serial;

/**
 * Parses JSON payloads from Kinesis messages (EventBridge S3 object-created events)
 * to extract S3 bucket URL and object name, emitting {@link S3Notification} POJOs.
 *
 * <p>Malformed JSON messages are logged, counted via a dead-letter metric counter,
 * and skipped so the Flink job continues processing subsequent messages.</p>
 */
public class MessageParser extends RichFlatMapFunction<String, S3Notification> {

    @Serial
    private static final long serialVersionUID = 1L;
    private static final Logger LOG = LoggerFactory.getLogger(MessageParser.class);

    private transient ObjectMapper objectMapper;
    private transient Counter deadLetterCounter;

    @Override
    public void open(OpenContext openContext) {
        this.objectMapper = new ObjectMapper();
        this.deadLetterCounter = getRuntimeContext()
                .getMetricGroup()
                .counter("deadLetterMessages");
    }

    @Override
    public void flatMap(String value, Collector<S3Notification> out) {
        try {
            JsonNode root = objectMapper.readTree(value);

            JsonNode detailNode = root.path("detail");
            String bucketName = detailNode.path("bucket").path("name").asText(null);
            String objectKey = detailNode.path("object").path("key").asText(null);

            if (bucketName == null || bucketName.isEmpty()
                    || objectKey == null || objectKey.isEmpty()) {
                LOG.error("Missing required fields (bucket name or object key) in message: {}", value);
                deadLetterCounter.inc();
                return;
            }

            String bucketUrl = "s3://" + bucketName;
            String eventTime = root.path("time").asText(null);
            String eventSource = root.path("source").asText(null);

            S3Notification notification = new S3Notification(bucketUrl, objectKey, eventTime, eventSource);
            out.collect(notification);
        } catch (Exception e) {
            LOG.error("Failed to parse Kinesis message: {}", value, e);
            deadLetterCounter.inc();
        }
    }
}
