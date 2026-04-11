package org.muralis.datahose.model;

import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.ToString;

import java.io.Serial;
import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * POJO representing a transaction log entry written to the RDS PostgreSQL database.
 * <p>
 * Invariants enforced by the {@link Builder}:
 * <ul>
 *   <li>{@code recordsWritten <= recordsProcessed}</li>
 *   <li>{@code endTime >= startTime} (when both present)</li>
 *   <li>Required fields ({@code transactionId}, {@code sourceBucket}, {@code sourceObjectKey},
 *       {@code status}, {@code startTime}) must be non-null</li>
 *   <li>{@code errorMessage} is non-null if and only if {@code status} is FAILURE or PARTIAL</li>
 * </ul>
 */
@Getter
@EqualsAndHashCode
@ToString
public class TransactionRecord implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    public static final String STATUS_SUCCESS = "SUCCESS";
    public static final String STATUS_FAILURE = "FAILURE";
    public static final String STATUS_PARTIAL = "PARTIAL";

    @EqualsAndHashCode.Exclude @ToString.Exclude
    private static final Set<String> VALID_STATUSES = Set.of(STATUS_SUCCESS, STATUS_FAILURE, STATUS_PARTIAL);
    @EqualsAndHashCode.Exclude @ToString.Exclude
    private static final Set<String> ERROR_STATUSES = Set.of(STATUS_FAILURE, STATUS_PARTIAL);

    private final UUID transactionId;
    private final String sourceBucket;
    private final String sourceObjectKey;
    private final String status;
    private final Instant startTime;
    private final Instant endTime;
    private final long recordsProcessed;
    private final long recordsWritten;
    private final String errorMessage;
    private final String icebergTableName;

    private TransactionRecord(Builder builder) {
        this.transactionId = builder.transactionId;
        this.sourceBucket = builder.sourceBucket;
        this.sourceObjectKey = builder.sourceObjectKey;
        this.status = builder.status;
        this.startTime = builder.startTime;
        this.endTime = builder.endTime;
        this.recordsProcessed = builder.recordsProcessed;
        this.recordsWritten = builder.recordsWritten;
        this.errorMessage = builder.errorMessage;
        this.icebergTableName = builder.icebergTableName;
    }

    public static Builder builder() {
        return new Builder();
    }

    // ---- Builder with invariant enforcement ----

    public static class Builder {
        private UUID transactionId;
        private String sourceBucket;
        private String sourceObjectKey;
        private String status;
        private Instant startTime;
        private Instant endTime;
        private long recordsProcessed;
        private long recordsWritten;
        private String errorMessage;
        private String icebergTableName;

        private Builder() {}

        public Builder transactionId(UUID transactionId) { this.transactionId = transactionId; return this; }
        public Builder sourceBucket(String sourceBucket) { this.sourceBucket = sourceBucket; return this; }
        public Builder sourceObjectKey(String sourceObjectKey) { this.sourceObjectKey = sourceObjectKey; return this; }
        public Builder status(String status) { this.status = status; return this; }
        public Builder startTime(Instant startTime) { this.startTime = startTime; return this; }
        public Builder endTime(Instant endTime) { this.endTime = endTime; return this; }
        public Builder recordsProcessed(long recordsProcessed) { this.recordsProcessed = recordsProcessed; return this; }
        public Builder recordsWritten(long recordsWritten) { this.recordsWritten = recordsWritten; return this; }
        public Builder errorMessage(String errorMessage) { this.errorMessage = errorMessage; return this; }
        public Builder icebergTableName(String icebergTableName) { this.icebergTableName = icebergTableName; return this; }

        /**
         * Builds the {@link TransactionRecord}, enforcing all invariants.
         *
         * @return a validated TransactionRecord
         * @throws NullPointerException     if a required field is null
         * @throws IllegalArgumentException if any invariant is violated
         */
        public TransactionRecord build() {
            Objects.requireNonNull(transactionId, "transactionId must not be null");
            Objects.requireNonNull(sourceBucket, "sourceBucket must not be null");
            Objects.requireNonNull(sourceObjectKey, "sourceObjectKey must not be null");
            Objects.requireNonNull(status, "status must not be null");
            Objects.requireNonNull(startTime, "startTime must not be null");

            if (!VALID_STATUSES.contains(status)) {
                throw new IllegalArgumentException(
                        "status must be one of " + VALID_STATUSES + ", got: " + status);
            }
            if (recordsWritten > recordsProcessed) {
                throw new IllegalArgumentException(
                        "recordsWritten (" + recordsWritten
                                + ") must not exceed recordsProcessed (" + recordsProcessed + ")");
            }
            if (endTime != null && endTime.isBefore(startTime)) {
                throw new IllegalArgumentException(
                        "endTime (" + endTime + ") must not be before startTime (" + startTime + ")");
            }

            boolean isErrorStatus = ERROR_STATUSES.contains(status);
            if (isErrorStatus && errorMessage == null) {
                throw new IllegalArgumentException(
                        "errorMessage must not be null when status is " + status);
            }
            if (!isErrorStatus && errorMessage != null) {
                throw new IllegalArgumentException(
                        "errorMessage must be null when status is " + status
                                + ", got: " + errorMessage);
            }

            return new TransactionRecord(this);
        }
    }
}
