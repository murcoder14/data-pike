package org.muralis.datahose.processing;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.muralis.datahose.model.WeatherObservation;

import java.util.ArrayList;
import java.util.List;

final class JsonStructuredFileParser implements StructuredFileParser {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public List<WeatherObservation> parse(byte[] content) throws Exception {
        JsonNode root = objectMapper.readTree(content);
        List<WeatherObservation> rows = new ArrayList<>();
        if (root.isArray()) {
            for (JsonNode node : root) {
                rows.add(nodeToObservation(node));
            }
            return rows;
        }
        if (root.isObject() && root.has("records") && root.get("records").isArray()) {
            for (JsonNode node : root.get("records")) {
                rows.add(nodeToObservation(node));
            }
            return rows;
        }
        rows.add(nodeToObservation(root));
        return rows;
    }

    private WeatherObservation nodeToObservation(JsonNode node) {
        return objectMapper.convertValue(node, WeatherObservation.class);
    }
}