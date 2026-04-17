package org.muralis.datahose.configuration;

import java.util.Locale;

/**
 * Supported runtime execution modes.
 */
public enum ExecutionMode {
    LOCAL,
    CLOUD;

    /**
     * Parses a user-supplied value into an execution mode.
     * Defaults to CLOUD when value is null/blank.
     */
    public static ExecutionMode fromString(String value) {
        if (value == null || value.isBlank()) {
            return CLOUD;
        }

        String normalized = value.trim().toLowerCase(Locale.ROOT);
        return switch (normalized) {
            case "local", "--local", "mode=local", "--mode=local" -> LOCAL;
            case "cloud", "mode=cloud", "--mode=cloud" -> CLOUD;
            default -> throw new IllegalArgumentException(
                    "Unsupported execution mode '" + value + "'. Expected local or cloud.");
        };
    }
}
