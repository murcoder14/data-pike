package org.muralis.datahose.processing;

import org.apache.avro.Schema;

import java.io.IOException;
import java.io.InputStream;

public final class TemperatureSummarySchemas {

    public static final Schema TEMPERATURE_SUMMARY = loadSchema();

    private TemperatureSummarySchemas() {
    }

    private static Schema loadSchema() {
        try (InputStream inputStream = TemperatureSummarySchemas.class.getClassLoader()
                .getResourceAsStream("avro/temperature-summary.avsc")) {
            if (inputStream == null) {
                throw new IllegalStateException("Missing Avro schema resource avro/temperature-summary.avsc");
            }
            return new Schema.Parser().parse(inputStream);
        } catch (IOException exception) {
            throw new IllegalStateException("Failed to load temperature summary Avro schema", exception);
        }
    }
}