package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class ExternalServicePropertiesTest {

    @Test
    void maxIdleTimeDefaultsToDisabled() {
        ExternalServiceProperties properties = new ExternalServiceProperties();

        assertEquals(ExternalLeasingStrategy.FIFO, properties.getLeasingStrategy());
        assertEquals(0L, properties.getMaxIdleTimeMs());
        assertEquals(0L, properties.getBackgroundEvictionIntervalMs());
        assertDoesNotThrow(properties::validatePoolContract);
    }

    @Test
    void acceptsFreshFirstLifecyclePolicyValues() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setLeasingStrategy(ExternalLeasingStrategy.LIFO);
        properties.setMaxIdleTimeMs(3000);
        properties.setBackgroundEvictionIntervalMs(1000);

        assertDoesNotThrow(properties::validatePoolContract);
    }

    @Test
    void rejectsNegativeMaxIdleTime() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setMaxIdleTimeMs(-1);

        assertThrows(IllegalStateException.class, properties::validatePoolContract);
    }

    @Test
    void rejectsNegativeBackgroundEvictionInterval() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setBackgroundEvictionIntervalMs(-1);

        assertThrows(IllegalStateException.class, properties::validatePoolContract);
    }

    @Test
    void rejectsNullLeasingStrategy() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setLeasingStrategy(null);

        assertThrows(IllegalStateException.class, properties::validatePoolContract);
    }

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
