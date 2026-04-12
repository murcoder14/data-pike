package org.muralis.datahose.processing;

import org.muralis.datahose.model.WeatherObservation;

import java.util.List;

interface StructuredFileParser {
    List<WeatherObservation> parse(byte[] content) throws Exception;
}