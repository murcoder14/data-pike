package org.muralis.datahose.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serial;
import java.io.Serializable;

/**
 * POJO representing a parsed S3 object-created event notification received via Kinesis.
 */
@Data
@NoArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class S3Notification implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @JsonProperty("bucketUrl")
    private String bucketUrl;

    @JsonProperty("objectName")
    private String objectName;

    @JsonProperty("eventTime")
    private String eventTime;

    @JsonProperty("eventSource")
    private String eventSource;

    @JsonCreator
    public S3Notification(
            @JsonProperty("bucketUrl") String bucketUrl,
            @JsonProperty("objectName") String objectName,
            @JsonProperty("eventTime") String eventTime,
            @JsonProperty("eventSource") String eventSource) {
        this.bucketUrl = bucketUrl;
        this.objectName = objectName;
        this.eventTime = eventTime;
        this.eventSource = eventSource;
    }
}
