package com.letscook.platform.config;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Minimal membership lookup used by the STOMP inbound interceptor before room-topic subscription.
 */
@Repository
class WebSocketAccessRepository {
    private final JdbcClient jdbc;
    WebSocketAccessRepository(JdbcClient jdbc){this.jdbc=jdbc;}
    boolean isActiveMember(String roomId,String subject){return jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_members rm JOIN app_users u ON u.id=rm.user_id WHERE rm.room_id=CAST(:r AS UUID) AND u.identity_subject=:s AND rm.status='ACTIVE')").param("r",roomId).param("s",subject).query(Boolean.class).single();}
}
