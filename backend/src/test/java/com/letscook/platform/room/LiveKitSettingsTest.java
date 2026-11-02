package com.letscook.platform.room;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class LiveKitSettingsTest {
    @Test
    void cloudModeSelectsCloudEndpoint() {
        LiveKitSettings settings = new LiveKitSettings(
                "cloud", "wss://cloud.example", "cloud-key", "cloud-secret",
                "wss://router.example", "router-key", "router-secret");

        assertEquals("wss://cloud.example", settings.url());
        assertEquals("cloud-key", settings.apiKey());
    }

    @Test
    void routerAliasSelectsSelfHostedEndpoint() {
        LiveKitSettings settings = new LiveKitSettings(
                "router", "wss://cloud.example", "cloud-key", "cloud-secret",
                "wss://router.example", "router-key", "router-secret");

        assertEquals("wss://router.example", settings.url());
        assertEquals("router-key", settings.apiKey());
    }

    @Test
    void invalidModeFailsFast() {
        assertThrows(IllegalArgumentException.class, () -> new LiveKitSettings(
                "sometimes", "wss://cloud.example", "cloud-key", "cloud-secret",
                "wss://router.example", "router-key", "router-secret"));
    }
}
