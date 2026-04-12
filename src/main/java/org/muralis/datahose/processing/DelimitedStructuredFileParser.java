package org.muralis.datahose.processing;

import org.muralis.datahose.model.WeatherObservation;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

final class DelimitedStructuredFileParser implements StructuredFileParser {

    private final String delimiter;

    DelimitedStructuredFileParser(String delimiter) {
        this.delimiter = delimiter;
    }

    @Override
    public List<WeatherObservation> parse(byte[] content) throws Exception {
        List<WeatherObservation> rows = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new ByteArrayInputStream(content), StandardCharsets.UTF_8))) {
            String headerLine = readNextNonBlankLine(reader);
            if (headerLine == null) {
                return rows;
            }

            String[] headers = headerLine.split(Pattern.quote(delimiter), -1);
            for (int index = 0; index < headers.length; index++) {
                headers[index] = headers[index].trim();
            }

            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank()) {
                    continue;
                }
                String[] values = line.split(Pattern.quote(delimiter), -1);
                Map<String, String> row = new LinkedHashMap<>();
                for (int index = 0; index < headers.length; index++) {
                    row.put(headers[index], index < values.length ? values[index].trim() : "");
                }
                rows.add(toObservation(row));
            }
        }
        return rows;
    }

    private WeatherObservation toObservation(Map<String, String> row) {
        String date = requiredValue(row, "date");
        String city = requiredValue(row, "city");
        int temperature = Integer.parseInt(requiredValue(row, "temperature"));
        return new WeatherObservation(date, city, temperature);
    }

    private String requiredValue(Map<String, String> row, String key) {
        String value = row.entrySet().stream()
                .filter(entry -> entry.getKey().equalsIgnoreCase(key))
                .map(Map.Entry::getValue)
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Missing required column: " + key));
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Blank required column: " + key);
        }
        return value;
    }

    private String readNextNonBlankLine(BufferedReader reader) throws Exception {
        String line;
        while ((line = reader.readLine()) != null) {
            if (!line.isBlank()) {
                return line;
            }
        }
        return null;
    }
}