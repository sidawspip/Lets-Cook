package com.letscook.platform.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * STOMP API configuration for watch-state broadcasts and targeted user notifications.
 *
 * <p>Authenticates the bearer token on CONNECT and authorizes room watch-topic subscriptions
 * against active membership before allowing delivery.</p>
 */
@Configuration
@EnableWebSocketMessageBroker
public class WatchWebSocketConfig implements WebSocketMessageBrokerConfigurer {
    private final JwtDecoder jwtDecoder;
    private final WebSocketAccessRepository access;

    public WatchWebSocketConfig(JwtDecoder jwtDecoder, WebSocketAccessRepository access) {
        this.jwtDecoder = jwtDecoder;
        this.access = access;
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic", "/queue");
        registry.setApplicationDestinationPrefixes("/app");
        registry.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                // Mutate the accessor attached to the inbound message itself.
                // Wrapping creates a detached header view, so setUser() never
                // reached Spring's user registry and /user/queue notifications
                // had no authenticated session to target.
                StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
                if (accessor == null) return message;
                if (StompCommand.CONNECT.equals(accessor.getCommand())) {
                    String header = accessor.getFirstNativeHeader("Authorization");
                    if (header == null || !header.startsWith("Bearer ")) {
                        throw new IllegalArgumentException("Missing bearer token");
                    }
                    accessor.setUser(new JwtAuthenticationToken(jwtDecoder.decode(header.substring(7))));
                }
                if (StompCommand.SUBSCRIBE.equals(accessor.getCommand())) {
                    String destination=accessor.getDestination();
                    if(destination!=null&&destination.matches("/topic/rooms/[0-9a-fA-F-]+/(watch|chat)")){
                        if(!(accessor.getUser() instanceof JwtAuthenticationToken auth))throw new IllegalArgumentException("Unauthenticated subscription");
                        String room=destination.split("/")[3];String subject=auth.getToken().getSubject();
                        boolean member=access.isActiveMember(room,subject);
                        if(!member)throw new IllegalArgumentException("Room membership required");
                    }
                }
                return message;
            }
        });
    }
}
