package org.muralis.datahose.processing;

import org.muralis.datahose.model.WeatherObservation;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import javax.xml.parsers.DocumentBuilderFactory;
import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class XmlStructuredFileParser implements StructuredFileParser {

    @Override
    public List<WeatherObservation> parse(byte[] content) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(false);
        factory.setExpandEntityReferences(false);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);

        Document document = factory.newDocumentBuilder().parse(new ByteArrayInputStream(content));
        Element root = document.getDocumentElement();
        List<Element> childElements = directChildElements(root);
        if (childElements.isEmpty()) {
            return List.of();
        }

        boolean singleRecord = childElements.stream().noneMatch(this::hasDirectChildElements);
        if (singleRecord) {
            return List.of(elementToObservation(root));
        }

        List<WeatherObservation> rows = new ArrayList<>();
        for (Element child : childElements) {
            rows.add(elementToObservation(child));
        }
        return rows;
    }

    private WeatherObservation elementToObservation(Element element) {
        Map<String, String> row = new LinkedHashMap<>();
        for (Element child : directChildElements(element)) {
            row.put(child.getTagName().toLowerCase(), child.getTextContent().trim());
        }
        return new WeatherObservation(
                requiredValue(row, "date"),
                requiredValue(row, "city"),
                Integer.parseInt(requiredValue(row, "temperature")));
    }

    private String requiredValue(Map<String, String> row, String key) {
        String value = row.get(key);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Missing required XML element: " + key);
        }
        return value;
    }

    private boolean hasDirectChildElements(Element element) {
        return !directChildElements(element).isEmpty();
    }

    private List<Element> directChildElements(Element element) {
        NodeList childNodes = element.getChildNodes();
        List<Element> elements = new ArrayList<>();
        for (int index = 0; index < childNodes.getLength(); index++) {
            Node node = childNodes.item(index);
            if (node instanceof Element childElement) {
                elements.add(childElement);
            }
        }
        return elements;
    }
}