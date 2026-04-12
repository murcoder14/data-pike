package org.muralis.datahose.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.ToString;

import java.io.Serial;
import java.io.Serializable;
import java.util.Objects;

@Getter
@ToString
@EqualsAndHashCode
@JsonIgnoreProperties(ignoreUnknown = true)
public class WeatherObservation implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private final String date;
    private final String city;
    private final int temperature;

    @JsonCreator
    public WeatherObservation(
            @JsonProperty("date") String date,
            @JsonProperty("city") String city,
            @JsonProperty("temperature") int temperature) {
        this.date = Objects.requireNonNull(date, "date must not be null");
        this.city = Objects.requireNonNull(city, "city must not be null");
        this.temperature = temperature;
    }
}