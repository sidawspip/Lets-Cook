package com.letscook.platform.room;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Locale;

/** Resolves the active LiveKit deployment without leaking deployment choices into room logic. */
@Component
class LiveKitSettings {
    private final String mode;
    private final Endpoint cloud;
    private final Endpoint selfHosted;

    LiveKitSettings(
            @Value("${app.livekit.mode:self-hosted}") String mode,
            @Value("${app.livekit.cloud.url:}") String cloudUrl,
            @Value("${app.livekit.cloud.api-key:}") String cloudApiKey,
            @Value("${app.livekit.cloud.api-secret:}") String cloudApiSecret,
            @Value("${app.livekit.self-hosted.url:ws://localhost:7880}") String selfHostedUrl,
            @Value("${app.livekit.self-hosted.api-key:devkey}") String selfHostedApiKey,
            @Value("${app.livekit.self-hosted.api-secret:lets-cook-dev-livekit-secret-32-chars}") String selfHostedApiSecret) {
        this.mode = normalizeMode(mode);
        this.cloud = new Endpoint(cloudUrl, cloudApiKey, cloudApiSecret);
        this.selfHosted = new Endpoint(selfHostedUrl, selfHostedApiKey, selfHostedApiSecret);
        active().validate(this.mode);
    }

    String url() { return active().url(); }
    String apiKey() { return active().apiKey(); }
    String apiSecret() { return active().apiSecret(); }

    private Endpoint active() {
        return mode.equals("cloud") ? cloud : selfHosted;
    }

    private static String normalizeMode(String value) {
        String normalized = value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
        return switch (normalized) {
            case "cloud" -> "cloud";
            case "router", "self-hosted", "self_hosted", "local" -> "self-hosted";
            default -> throw new IllegalArgumentException(
                    "LIVEKIT_MODE must be 'cloud' or 'self-hosted' (the alias 'router' is also accepted)");
        };
    }

    private record Endpoint(String url, String apiKey, String apiSecret) {
        void validate(String mode) {
            if (url == null || url.isBlank() || apiKey == null || apiKey.isBlank()
                    || apiSecret == null || apiSecret.isBlank()) {
                throw new IllegalArgumentException("LiveKit " + mode + " URL, API key, and API secret are required");
            }
        }
    }
}
