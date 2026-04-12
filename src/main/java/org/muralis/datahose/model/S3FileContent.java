package org.muralis.datahose.model;

import org.jetbrains.annotations.NotNull;

import java.io.Serial;
import java.io.Serializable;
import java.util.Arrays;
import java.util.Objects;

/**
 * Wrapper pairing an {@link S3Notification} with the raw file content read from S3
 * and the detected file format.
 */
public record S3FileContent(S3Notification notification, byte[] content, FileFormat format) implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    public S3FileContent(S3Notification notification, byte[] content, FileFormat format) {
        this.notification = Objects.requireNonNull(notification, "notification must not be null");
        this.content = Objects.requireNonNull(content, "content must not be null");
        this.format = Objects.requireNonNull(format, "format must not be null");
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        S3FileContent that = (S3FileContent) o;
        return Objects.equals(notification, that.notification)
            && Arrays.equals(content, that.content)
            && format == that.format;
    }

    @Override
    public int hashCode() {
        int result = Objects.hash(notification);
        result = 31 * result + Arrays.hashCode(content);
        result = 31 * result + format.hashCode();
        return result;
    }

    @Override
    public @NotNull String toString() {
        return "S3FileContent{"
                + "notification=" + notification
                + ", contentLength=" + content.length
                + ", format=" + format
                + '}';
    }
}
