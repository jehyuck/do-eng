package com.example.doenggameflux.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.transport-attribution")
@Getter
@Setter
public class TransportAttributionProperties {

    private boolean enabled = false;
}
