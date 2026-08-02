package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class ExternalServicePropertiesTest {

    @Test
    void acceptsEqualSharedAndIsolatedBudgets() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setPoolMode(ExternalPoolMode.ISOLATED);
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(400, 800));

        assertDoesNotThrow(properties::validatePoolContract);
    }

    @Test
    void rejectsUnequalIsolatedBudgets() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setPoolMode(ExternalPoolMode.ISOLATED);
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(400, 800));
        properties.setAiPool(new ExternalServiceProperties.PoolSettings(300, 600));

        assertThrows(IllegalStateException.class, properties::validatePoolContract);
    }

    @Test
    void rejectsNonPositivePoolSetting() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(0, 800));

        assertThrows(IllegalStateException.class, properties::validatePoolContract);
    }
}
