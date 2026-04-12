package org.muralis.datahose.processing;

import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.io.Serial;

/**
 * Reads source files from S3 using the bucket URL and object name extracted from
 * {@link S3Notification} events. Emits {@link S3FileContent} pairing the notification
 * metadata with the raw file bytes.
 *
 * <p>Error handling:
 * <ul>
 *   <li>{@link NoSuchKeyException}: logged and skipped (no output emitted)</li>
 *   <li>Transient S3 errors: retried with exponential backoff (3 attempts, 1s/2s/4s)</li>
 * </ul>
 */
public class S3FileReader extends RichFlatMapFunction<S3Notification, S3FileContent> {

    @Serial
    private static final long serialVersionUID = 1L;
    private static final Logger LOG = LoggerFactory.getLogger(S3FileReader.class);

    private static final int MAX_RETRIES = 3;
    private static final long[] RETRY_DELAYS_MS = {1000L, 2000L, 4000L};
    private static final String S3_PREFIX = "s3://";

    private transient S3Client s3Client;

    /** No-arg constructor uses default S3 client (production path). */
    public S3FileReader() {
    }

    /**
     * Constructor accepting an externally-provided S3 client (for testing).
     */
    public S3FileReader(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    @Override
    public void open(OpenContext openContext) {
        if (this.s3Client == null) {
            this.s3Client = S3Client.create();
        }
    }

    @Override
    public void flatMap(S3Notification notification, Collector<S3FileContent> out) {
        String bucketName = extractBucketName(notification.getBucketUrl());
        String objectKey = notification.getObjectName();

        LOG.info("Reading s3://{}/{}", bucketName, objectKey);

        try {
            byte[] content = readWithRetry(bucketName, objectKey);
            FileFormat format = FileFormatDetector.detect(notification, content);
            out.collect(new S3FileContent(notification, content, format));
        } catch (NoSuchKeyException e) {
            LOG.error("S3 object not found: s3://{}/{}. Skipping.", bucketName, objectKey, e);
            // No output emitted — TransactionLogger handles FAILURE recording separately
        } catch (S3Exception e) {
            LOG.error("Failed to read s3://{}/{} after {} retries: {}",
                    bucketName, objectKey, MAX_RETRIES, e.getMessage(), e);
            // Transient errors exhausted — no output emitted
        }
    }

    /**
     * Reads an S3 object with exponential backoff retry for transient errors.
     * {@link NoSuchKeyException} is thrown immediately (not retried).
     */
    byte[] readWithRetry(String bucketName, String objectKey) {
        GetObjectRequest request = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(objectKey)
                .build();

        S3Exception lastException = null;

        for (int attempt = 0; attempt < MAX_RETRIES; attempt++) {
            try {
                ResponseBytes<GetObjectResponse> response = s3Client.getObjectAsBytes(request);
                return response.asByteArray();
            } catch (NoSuchKeyException e) {
                // Not transient — propagate immediately
                throw e;
            } catch (S3Exception e) {
                lastException = e;
                if (attempt < MAX_RETRIES - 1) {
                    long delay = RETRY_DELAYS_MS[attempt];
                    LOG.warn("Transient S3 error reading s3://{}/{} (attempt {}/{}). Retrying in {}ms.",
                            bucketName, objectKey, attempt + 1, MAX_RETRIES, delay, e);
                    sleep(delay);
                }
            }
        }

        throw lastException;
    }

    /**
     * Extracts the bucket name from an S3 URL by stripping the "s3://" prefix.
     * Also handles trailing slashes.
     */
    static String extractBucketName(String bucketUrl) {
        if (bucketUrl == null) {
            throw new IllegalArgumentException("bucketUrl must not be null");
        }
        String name = bucketUrl;
        if (name.startsWith(S3_PREFIX)) {
            name = name.substring(S3_PREFIX.length());
        }
        // Strip trailing slash if present
        if (name.endsWith("/")) {
            name = name.substring(0, name.length() - 1);
        }
        return name;
    }

    static FileFormat detectFormat(S3Notification notification, byte[] content) {
        return FileFormatDetector.detect(notification, content);
    }

    /** Sleeps for the given duration; extracted for testability. */
    void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.warn("Retry sleep interrupted", e);
        }
    }

    @Override
    public void close() {
        if (s3Client != null) {
            s3Client.close();
            s3Client = null;
        }
    }
}
