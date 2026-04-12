package org.muralis.datahose.processing;

import org.muralis.datahose.model.FileFormat;
import org.muralis.datahose.model.S3FileContent;
import org.muralis.datahose.model.S3Notification;
import org.apache.flink.util.Collector;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class S3FileReaderTest {

    private StubS3Client stubS3;
    private TestableS3FileReader reader;
    private ListCollector collector;

    @BeforeEach
    void setUp() {
        stubS3 = new StubS3Client();
        reader = new TestableS3FileReader(stubS3);
        collector = new ListCollector();
    }

    @Test
    void successfulRead_emitsS3FileContent() {
        byte[] data = "file-content".getBytes(StandardCharsets.UTF_8);
        stubS3.setResponse(data);

        S3Notification notification = new S3Notification(
                "s3://my-bucket", "data/file.csv", "2024-01-15T10:00:00Z", "aws:s3");

        reader.flatMap(notification, collector);

        assertEquals(1, collector.collected.size());
        S3FileContent result = collector.collected.get(0);
        assertSame(notification, result.notification());
        assertArrayEquals(data, result.content());
        assertEquals(FileFormat.CSV, result.format());
        assertEquals("my-bucket", stubS3.lastRequestedBucket);
        assertEquals("data/file.csv", stubS3.lastRequestedKey);
    }

    @Test
    void noSuchKey_skipsWithoutEmitting() {
        stubS3.setNoSuchKeyException();

        S3Notification notification = new S3Notification(
                "s3://my-bucket", "missing.csv", "2024-01-15T10:00:00Z", "aws:s3");

        reader.flatMap(notification, collector);

        assertTrue(collector.collected.isEmpty());
    }

    @Test
    void transientError_retriesThenEmits() {
        byte[] data = "recovered".getBytes(StandardCharsets.UTF_8);
        // Fail twice, then succeed on third attempt
        stubS3.setFailThenSucceed(2, data);

        S3Notification notification = new S3Notification(
                "s3://my-bucket", "data/file.csv", "2024-01-15T10:00:00Z", "aws:s3");

        reader.flatMap(notification, collector);

        assertEquals(1, collector.collected.size());
        assertArrayEquals(data, collector.collected.get(0).content());
        assertEquals(3, stubS3.callCount);
        assertEquals(2, reader.sleepCalls.size());
        assertEquals(1000L, reader.sleepCalls.get(0));
        assertEquals(2000L, reader.sleepCalls.get(1));
    }

    @Test
    void transientError_exhaustsRetries_skipsWithoutEmitting() {
        stubS3.setAlwaysFail();

        S3Notification notification = new S3Notification(
                "s3://my-bucket", "data/file.csv", "2024-01-15T10:00:00Z", "aws:s3");

        reader.flatMap(notification, collector);

        assertTrue(collector.collected.isEmpty());
        assertEquals(3, stubS3.callCount);
        assertEquals(2, reader.sleepCalls.size());
    }

    @Test
    void extractBucketName_stripsS3Prefix() {
        assertEquals("my-bucket", S3FileReader.extractBucketName("s3://my-bucket"));
    }

    @Test
    void extractBucketName_stripsTrailingSlash() {
        assertEquals("my-bucket", S3FileReader.extractBucketName("s3://my-bucket/"));
    }

    @Test
    void extractBucketName_handlesNoPrefixGracefully() {
        assertEquals("my-bucket", S3FileReader.extractBucketName("my-bucket"));
    }

    @Test
    void extractBucketName_nullThrows() {
        assertThrows(IllegalArgumentException.class, () -> S3FileReader.extractBucketName(null));
    }

    @Test
    void detectFormat_identifiesJsonFromContent() {
        S3Notification notification = new S3Notification(
                "s3://my-bucket", "unknown.dat", "2024-01-15T10:00:00Z", "aws:s3");

        assertEquals(FileFormat.JSON,
                S3FileReader.detectFormat(notification, "[{\"name\":\"Alice\"}]".getBytes(StandardCharsets.UTF_8)));
    }

    // ---- Test helpers ----

    /** S3FileReader subclass that captures sleep calls instead of actually sleeping. */
    static class TestableS3FileReader extends S3FileReader {
        final List<Long> sleepCalls = new ArrayList<>();

        TestableS3FileReader(S3Client s3Client) {
            super(s3Client);
        }

        @Override
        void sleep(long millis) {
            sleepCalls.add(millis);
        }
    }

    /** Simple Collector that accumulates emitted elements. */
    static class ListCollector implements Collector<S3FileContent> {
        final List<S3FileContent> collected = new ArrayList<>();

        @Override
        public void collect(S3FileContent record) {
            collected.add(record);
        }

        @Override
        public void close() {
        }
    }

    /** Stub S3Client that can be configured to return data, throw NoSuchKeyException, or fail transiently. */
    static class StubS3Client implements S3Client {
        String lastRequestedBucket;
        String lastRequestedKey;
        int callCount = 0;

        private byte[] responseData;
        private boolean throwNoSuchKey = false;
        private boolean alwaysFail = false;
        private int failCount = 0;
        private int failBeforeSuccess = 0;

        void setResponse(byte[] data) {
            this.responseData = data;
        }

        void setNoSuchKeyException() {
            this.throwNoSuchKey = true;
        }

        void setAlwaysFail() {
            this.alwaysFail = true;
        }

        void setFailThenSucceed(int failTimes, byte[] data) {
            this.failBeforeSuccess = failTimes;
            this.responseData = data;
        }

        @Override
        public ResponseBytes<GetObjectResponse> getObjectAsBytes(GetObjectRequest request) {
            callCount++;
            lastRequestedBucket = request.bucket();
            lastRequestedKey = request.key();

            if (throwNoSuchKey) {
                throw NoSuchKeyException.builder()
                        .message("The specified key does not exist.")
                        .build();
            }
            if (alwaysFail) {
                throw S3Exception.builder()
                        .message("Service unavailable")
                        .statusCode(503)
                        .build();
            }
            if (failCount < failBeforeSuccess) {
                failCount++;
                throw S3Exception.builder()
                        .message("Service unavailable")
                        .statusCode(503)
                        .build();
            }
            return ResponseBytes.fromByteArray(GetObjectResponse.builder().build(), responseData);
        }

        @Override
        public String serviceName() {
            return "s3";
        }

        @Override
        public void close() {
        }
    }
}
