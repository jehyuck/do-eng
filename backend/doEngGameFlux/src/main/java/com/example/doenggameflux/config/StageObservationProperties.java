package com.example.doenggameflux.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.stage-observation")
@Getter
@Setter
public class StageObservationProperties {

    private boolean enabled = false;
}
