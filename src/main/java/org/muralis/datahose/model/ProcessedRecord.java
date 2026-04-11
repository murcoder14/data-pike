package org.muralis.datahose.model;

import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.ToString;

import java.io.Serial;
import java.io.Serializable;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Carries processed data plus metadata needed by both {@code IcebergSink} and
 * {@code TransactionLogger}.
 *
 * <p>Each instance represents the result of processing a single S3 file. It contains
 * the parsed data rows (as maps of column-name to value), source metadata from the
 * original notification, and processing outcome information (status, counts, errors).
 */
@Getter
@EqualsAndHashCode
@ToString
public class ProcessedRecord implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    public static final String STATUS_SUCCESS = "SUCCESS";
    public static final String STATUS_FAILURE = "FAILURE";
    public static final String STATUS_PARTIAL = "PARTIAL";

    private final S3Notification sourceNotification;
    @ToString.Exclude
    private final List<Map<String, String>> rows;
    private final String status;
    private final long recordsProcessed;
    private final long recordsWritten;
    private final String errorMessage;
    private final Instant processingTime;

    private ProcessedRecord(Builder builder) {
        this.sourceNotification = builder.sourceNotification;
        this.rows = builder.rows == null ? Collections.emptyList() : Collections.unmodifiableList(builder.rows);
        this.status = builder.status;
        this.recordsProcessed = builder.recordsProcessed;
        this.recordsWritten = builder.recordsWritten;
        this.errorMessage = builder.errorMessage;
        this.processingTime = builder.processingTime;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
        private S3Notification sourceNotification;
        private List<Map<String, String>> rows;
        private String status;
        private long recordsProcessed;
        private long recordsWritten;
        private String errorMessage;
        private Instant processingTime;

        private Builder() {}

        public Builder sourceNotification(S3Notification sourceNotification) { this.sourceNotification = sourceNotification; return this; }
        public Builder rows(List<Map<String, String>> rows) { this.rows = rows; return this; }
        public Builder status(String status) { this.status = status; return this; }
        public Builder recordsProcessed(long recordsProcessed) { this.recordsProcessed = recordsProcessed; return this; }
        public Builder recordsWritten(long recordsWritten) { this.recordsWritten = recordsWritten; return this; }
        public Builder errorMessage(String errorMessage) { this.errorMessage = errorMessage; return this; }
        public Builder processingTime(Instant processingTime) { this.processingTime = processingTime; return this; }

        public ProcessedRecord build() {
            Objects.requireNonNull(sourceNotification, "sourceNotification must not be null");
            Objects.requireNonNull(status, "status must not be null");
            Objects.requireNonNull(processingTime, "processingTime must not be null");
            return new ProcessedRecord(this);
        }
    }
}
