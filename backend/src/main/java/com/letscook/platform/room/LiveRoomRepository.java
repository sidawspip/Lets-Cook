package com.letscook.platform.room;

import static com.letscook.platform.room.LiveRoomModels.*;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Persistence for live presence, room sessions, active participants, recent people, room chat,
 * party-empty detection, and host succession data.
 */
@Repository
public class LiveRoomRepository {
    private final JdbcClient jdbc;

    public LiveRoomRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public void upsertPresence(UUID roomId, UUID userId) {
        jdbc.sql("""
                        INSERT INTO room_live_presence(room_id,user_id) VALUES(:room,:user)
                        ON CONFLICT(room_id,user_id) DO UPDATE SET last_seen_at=now()
                        """)
                .param("room", roomId).param("user", userId).update();
    }

    public void clearEmptySince(UUID roomId) {
        jdbc.sql("UPDATE rooms SET empty_since=NULL WHERE id=:room")
                .param("room", roomId).update();
    }

    public boolean startSession(UUID id, UUID roomId, UUID userId) {
        return jdbc.sql("""
                        INSERT INTO user_room_sessions(id,user_id,room_id) VALUES(:id,:user,:room)
                        ON CONFLICT(user_id,room_id) WHERE left_at IS NULL DO NOTHING
                        """)
                .param("id", id).param("user", userId).param("room", roomId).update() > 0;
    }

    public void touchPresence(UUID roomId, UUID userId) {
        jdbc.sql("UPDATE room_live_presence SET last_seen_at=now() WHERE room_id=:room AND user_id=:user")
                .param("room", roomId).param("user", userId).update();
    }

    public boolean finishSession(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        UPDATE user_room_sessions
                        SET left_at=now(),duration_seconds=GREATEST(0,EXTRACT(EPOCH FROM now()-joined_at)::bigint)
                        WHERE user_id=:user AND room_id=:room AND left_at IS NULL
                        """)
                .param("room", roomId).param("user", userId).update() > 0;
    }

    public boolean finishStaleSession(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        UPDATE user_room_sessions s
                        SET left_at=COALESCE(p.last_seen_at,now()),
                            duration_seconds=GREATEST(0,EXTRACT(EPOCH FROM COALESCE(p.last_seen_at,now())-s.joined_at)::bigint)
                        FROM room_live_presence p
                        WHERE s.user_id=:user AND s.room_id=:room AND s.left_at IS NULL
                          AND p.user_id=s.user_id AND p.room_id=s.room_id
                          AND p.last_seen_at<now()-interval '45 seconds'
                        """)
                .param("room", roomId).param("user", userId).update() > 0;
    }

    public void finishAllStaleSessions() {
        jdbc.sql("""
                        UPDATE user_room_sessions s
                        SET left_at=p.last_seen_at,
                            duration_seconds=GREATEST(0,EXTRACT(EPOCH FROM p.last_seen_at-s.joined_at)::bigint)
                        FROM room_live_presence p
                        WHERE s.user_id=p.user_id AND s.room_id=p.room_id AND s.left_at IS NULL
                          AND p.last_seen_at<now()-interval '45 seconds'
                        """).update();
        jdbc.sql("DELETE FROM room_live_presence WHERE last_seen_at<now()-interval '45 seconds'").update();
    }

    public void deletePresence(UUID roomId, UUID userId) {
        jdbc.sql("DELETE FROM room_live_presence WHERE room_id=:room AND user_id=:user")
                .param("room", roomId).param("user", userId).update();
    }

    public List<Participant> participants(UUID roomId) {
        return jdbc.sql("""
                        SELECT u.id,u.username,u.display_name,u.avatar_url,rm.role,
                               rm.can_share_screen,rm.can_add_videos,rm.can_view_video,
                               rm.video_access_requested
                        FROM room_live_presence p
                        JOIN app_users u ON u.id=p.user_id
                        JOIN room_members rm ON rm.room_id=p.room_id AND rm.user_id=p.user_id
                        WHERE p.room_id=:room
                        ORDER BY CASE rm.role WHEN 'HOST' THEN 0 WHEN 'CO_HOST' THEN 1 ELSE 2 END,u.display_name
                        """)
                .param("room", roomId)
                .query((rs, row) -> new Participant(
                        rs.getObject("id", UUID.class), rs.getString("username"),
                        rs.getString("display_name"), rs.getString("avatar_url"),
                        RoomRole.valueOf(rs.getString("role")), rs.getBoolean("can_share_screen"),
                        rs.getBoolean("can_add_videos"), rs.getBoolean("can_view_video"),
                        rs.getBoolean("video_access_requested")))
                .list();
    }

    public void rememberRecentPeople(UUID roomId, UUID viewerId) {
        jdbc.sql("""
                        INSERT INTO user_recent_room_people(viewer_id,seen_user_id,room_id,last_seen_at)
                        SELECT :viewer,p.user_id,:room,now() FROM room_live_presence p
                        WHERE p.room_id=:room AND p.user_id<>:viewer
                        ON CONFLICT(viewer_id,seen_user_id)
                        DO UPDATE SET room_id=EXCLUDED.room_id,last_seen_at=now()
                        """)
                .param("viewer", viewerId).param("room", roomId).update();
    }

    public List<RecentPerson> recentPeople(UUID viewerId) {
        return jdbc.sql("""
                        SELECT u.id,u.username,u.display_name,u.avatar_url,r.name room_name,x.last_seen_at,
                          EXISTS(SELECT 1 FROM friendships f
                            WHERE ((f.requester_id=:viewer AND f.addressee_id=u.id)
                              OR (f.addressee_id=:viewer AND f.requester_id=u.id))
                              AND f.status='ACCEPTED') friend
                        FROM user_recent_room_people x
                        JOIN app_users u ON u.id=x.seen_user_id JOIN rooms r ON r.id=x.room_id
                        WHERE x.viewer_id=:viewer
                          AND NOT EXISTS(SELECT 1 FROM user_blocks b
                            WHERE (b.blocker_id=:viewer AND b.blocked_id=u.id)
                               OR (b.blocker_id=u.id AND b.blocked_id=:viewer))
                        ORDER BY x.last_seen_at DESC LIMIT 500
                        """)
                .param("viewer", viewerId)
                .query((rs, row) -> new RecentPerson(
                        rs.getObject("id", UUID.class), rs.getString("username"),
                        rs.getString("display_name"), rs.getString("avatar_url"),
                        rs.getString("room_name"), rs.getTimestamp("last_seen_at").toInstant(),
                        rs.getBoolean("friend")))
                .list();
    }

    public List<ChatMessage> messages(UUID roomId, UUID viewerId) {
        List<ChatMessage> messages = jdbc.sql("""
                        SELECT m.id,m.sender_id,u.display_name,u.username,u.avatar_url,m.body,m.message_type,
                               m.media_provider,m.media_id,m.media_title,m.created_at,
                               reply.id reply_id,reply.sender_id reply_sender_id,reply_user.display_name reply_sender_name,
                               reply_user.username reply_sender_username,
                               reply.body reply_body,reply.message_type reply_type
                        FROM room_session_messages m
                        JOIN app_users u ON u.id=m.sender_id
                        LEFT JOIN room_session_messages reply ON reply.id=m.reply_to_message_id
                        LEFT JOIN app_users reply_user ON reply_user.id=reply.sender_id
                        WHERE m.room_id=:room
                          AND m.created_at >= COALESCE((
                            SELECT joined_at FROM user_room_sessions
                            WHERE room_id=:room AND user_id=:viewer AND left_at IS NULL
                            ORDER BY joined_at DESC LIMIT 1
                          ),now())
                        ORDER BY m.created_at DESC LIMIT 300
                        """)
                .param("room", roomId).param("viewer", viewerId)
                .query((rs, row) -> new ChatMessage(
                        rs.getObject("id", UUID.class), rs.getObject("sender_id", UUID.class),
                        rs.getString("display_name"),rs.getString("username"), rs.getString("avatar_url"),
                        rs.getString("body"), rs.getString("message_type"),
                        rs.getObject("reply_id",UUID.class)==null ? null : new ReplyPreview(
                                rs.getObject("reply_id",UUID.class),rs.getObject("reply_sender_id",UUID.class),
                                rs.getString("reply_sender_name"),rs.getString("reply_sender_username"),
                                rs.getString("reply_body"),rs.getString("reply_type")),
                        List.of(),rs.getString("media_provider"),rs.getString("media_id"),
                        rs.getString("media_title"),rs.getTimestamp("created_at").toInstant()))
                .list();
        Collections.reverse(messages);
        Map<UUID,List<ChatReaction>> reactions = new HashMap<>();
        jdbc.sql("""
                        SELECT x.message_id,x.reaction,count(*) reaction_count,
                               bool_or(x.user_id=:viewer) reacted_by_me
                        FROM room_message_reactions x
                        JOIN room_session_messages m ON m.id=x.message_id
                        WHERE m.room_id=:room
                          AND m.created_at >= COALESCE((
                            SELECT joined_at FROM user_room_sessions
                            WHERE room_id=:room AND user_id=:viewer AND left_at IS NULL
                            ORDER BY joined_at DESC LIMIT 1
                          ),now())
                        GROUP BY x.message_id,x.reaction ORDER BY min(x.created_at)
                        """).param("room",roomId).param("viewer",viewerId)
                .query((rs,row)->new ReactionRow(rs.getObject("message_id",UUID.class),
                        rs.getString("reaction"),rs.getInt("reaction_count"),rs.getBoolean("reacted_by_me")))
                .list().forEach(value->reactions.computeIfAbsent(value.messageId(),ignored->new ArrayList<>())
                        .add(new ChatReaction(value.reaction(),value.count(),value.reactedByMe())));
        return messages.stream().map(message->new ChatMessage(message.id(),message.senderId(),message.senderName(),
                message.senderUsername(),message.avatarUrl(),message.body(),message.type(),message.replyTo(),
                List.copyOf(reactions.getOrDefault(message.id(),List.of())),message.mediaProvider(),
                message.mediaId(),message.mediaTitle(),message.createdAt())).toList();
    }

    public void insertMessage(UUID id, UUID roomId, UUID senderId, String body, UUID replyToId, Instant createdAt) {
        jdbc.sql("""
                        INSERT INTO room_session_messages(id,room_id,sender_id,body,message_type,reply_to_message_id,created_at)
                        VALUES(:id,:room,:sender,:body,'MESSAGE',:reply,:at)
                        """)
                .param("id", id).param("room", roomId).param("sender", senderId)
                .param("body", body).param("reply",replyToId).param("at", Timestamp.from(createdAt)).update();
    }

    public void insertSystemEvent(UUID id,UUID roomId,UUID actorId,String body,String type,Instant createdAt) {
        jdbc.sql("""
                INSERT INTO room_session_messages(id,room_id,sender_id,body,message_type,created_at)
                VALUES(:id,:room,:actor,:body,:type,now())
                """).param("id",id).param("room",roomId).param("actor",actorId).param("body",body)
                .param("type",type).update();
    }

    public void insertVideoEvent(UUID id,UUID roomId,UUID actorId,String provider,String mediaId,String title,Instant createdAt) {
        jdbc.sql("""
                INSERT INTO room_session_messages(id,room_id,sender_id,body,message_type,media_provider,media_id,media_title,created_at)
                VALUES(:id,:room,:actor,:body,'VIDEO',:provider,:media,:title,:at)
                """).param("id",id).param("room",roomId).param("actor",actorId)
                .param("body","started playing "+title).param("provider",provider).param("media",mediaId)
                .param("title",title).param("at",Timestamp.from(createdAt)).update();
    }

    public boolean messageExists(UUID roomId,UUID messageId) {
        return jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_session_messages WHERE id=:id AND room_id=:room)")
                .param("id",messageId).param("room",roomId).query(Boolean.class).single();
    }

    public boolean hasReaction(UUID messageId,UUID userId,String reaction) {
        return jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_message_reactions WHERE message_id=:message AND user_id=:user AND reaction=:reaction)")
                .param("message",messageId).param("user",userId).param("reaction",reaction).query(Boolean.class).single();
    }

    public void addReaction(UUID messageId,UUID userId,String reaction) {
        jdbc.sql("INSERT INTO room_message_reactions(message_id,user_id,reaction) VALUES(:message,:user,:reaction) ON CONFLICT DO NOTHING")
                .param("message",messageId).param("user",userId).param("reaction",reaction).update();
    }

    public void deleteReaction(UUID messageId,UUID userId,String reaction) {
        jdbc.sql("DELETE FROM room_message_reactions WHERE message_id=:message AND user_id=:user AND reaction=:reaction")
                .param("message",messageId).param("user",userId).param("reaction",reaction).update();
    }

    public Optional<MentionTarget> activeMentionTarget(UUID roomId,String username) {
        return jdbc.sql("""
                SELECT u.id,u.identity_subject,u.haptic_feedback
                FROM app_users u JOIN room_live_presence p ON p.user_id=u.id
                WHERE p.room_id=:room AND lower(u.username)=lower(:username)
                """).param("room",roomId).param("username",username)
                .query((rs,row)->new MentionTarget(rs.getObject("id",UUID.class),rs.getString("identity_subject"),
                        rs.getBoolean("haptic_feedback"))).optional();
    }

    public void deleteStalePresence(UUID roomId) {
        jdbc.sql("DELETE FROM room_live_presence WHERE room_id=:room AND last_seen_at < now()-interval '45 seconds'")
                .param("room", roomId).update();
    }

    public List<UUID> stalePresenceUserIds(UUID roomId) {
        return jdbc.sql("SELECT user_id FROM room_live_presence WHERE room_id=:room AND last_seen_at < now()-interval '45 seconds'")
                .param("room",roomId).query(UUID.class).list();
    }

    public boolean isEmpty(UUID roomId) {
        return jdbc.sql("SELECT NOT EXISTS(SELECT 1 FROM room_live_presence WHERE room_id=:room)")
                .param("room", roomId).query(Boolean.class).single();
    }

    public boolean isEphemeral(UUID roomId) {
        return jdbc.sql("SELECT COALESCE((SELECT ephemeral FROM rooms WHERE id=:room),false)")
                .param("room", roomId).query(Boolean.class).single();
    }

    public void markEmpty(UUID roomId) {
        jdbc.sql("UPDATE rooms SET empty_since=COALESCE(empty_since,now()) WHERE id=:room")
                .param("room", roomId).update();
    }

    public void deleteMessages(UUID roomId) {
        jdbc.sql("DELETE FROM room_session_messages WHERE room_id=:room")
                .param("room", roomId).update();
    }

    public boolean hostPresent(UUID roomId) {
        return jdbc.sql("""
                        SELECT EXISTS(SELECT 1 FROM room_live_presence p
                          JOIN room_members m ON m.room_id=p.room_id AND m.user_id=p.user_id
                          WHERE p.room_id=:room AND m.role='HOST')
                        """)
                .param("room", roomId).query(Boolean.class).single();
    }

    public Optional<UUID> nextLeader(UUID roomId) {
        return jdbc.sql("""
                        SELECT p.user_id FROM room_live_presence p
                        JOIN room_members m ON m.room_id=p.room_id AND m.user_id=p.user_id
                        WHERE p.room_id=:room AND m.status='ACTIVE'
                        ORDER BY CASE m.role WHEN 'CO_HOST' THEN 0 WHEN 'MODERATOR' THEN 1 ELSE 2 END,
                          p.joined_at LIMIT 1
                        """)
                .param("room", roomId).query(UUID.class).optional();
    }

    public void promoteLeader(UUID roomId, UUID userId) {
        jdbc.sql("UPDATE room_members SET role='CO_HOST' WHERE room_id=:room AND role='HOST'")
                .param("room", roomId).update();
        jdbc.sql("""
                        UPDATE room_members SET role='HOST',can_share_screen=true,can_add_videos=true
                        WHERE room_id=:room AND user_id=:user
                        """)
                .param("room", roomId).param("user", userId).update();
        jdbc.sql("UPDATE rooms SET owner_id=:user,updated_at=now() WHERE id=:room")
                .param("user", userId).param("room", roomId).update();
    }

    public boolean isActiveMember(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT EXISTS(SELECT 1 FROM room_members
                          WHERE room_id=:room AND user_id=:user AND status='ACTIVE')
                        """)
                .param("room", roomId).param("user", userId).query(Boolean.class).single();
    }

    public boolean isPresent(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT EXISTS(SELECT 1 FROM room_live_presence
                          WHERE room_id=:room AND user_id=:user)
                        """)
                .param("room", roomId).param("user", userId).query(Boolean.class).single();
    }

    private record ReactionRow(UUID messageId,String reaction,int count,boolean reactedByMe) {}
}
