package com.letscook.platform.room;

import static com.letscook.platform.room.WatchQueueModels.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** SQL persistence for the room watch queue. No HTTP or policy decisions live here. */
/**
 * Queue persistence and ranking projections for unique media, selectors, votes, personal order,
 * skip thresholds, queue policy, and per-member add-video permission.
 */
@Repository
public class WatchQueueRepository {
    private final JdbcClient jdbc;

    public WatchQueueRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public boolean isActiveMember(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT EXISTS(
                            SELECT 1 FROM room_members
                            WHERE room_id=:roomId AND user_id=:userId AND status='ACTIVE'
                        )
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(Boolean.class)
                .single();
    }

    public Optional<String> role(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT role FROM room_members
                        WHERE room_id=:roomId AND user_id=:userId AND status='ACTIVE'
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(String.class)
                .optional();
    }

    public boolean canAdd(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT rm.role IN ('HOST','CO_HOST')
                            OR rooms.watch_queue_mode='VOTE'
                            OR (rooms.watch_queue_mode='PERMISSION' AND rm.can_add_videos)
                        FROM room_members rm
                        JOIN rooms ON rooms.id=rm.room_id
                        WHERE rm.room_id=:roomId AND rm.user_id=:userId AND rm.status='ACTIVE'
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(Boolean.class)
                .optional()
                .orElse(false);
    }

    public QueueSettings settings(UUID roomId) {
        return jdbc.sql("""
                        SELECT watch_queue_mode, watch_transition_seconds
                        FROM rooms WHERE id=:roomId
                        """)
                .param("roomId", roomId)
                .query((rs, row) -> new QueueSettings(rs.getString(1), rs.getInt(2)))
                .single();
    }

    public List<QueueItem> queuedItems(UUID roomId, UUID currentUserId) {
        List<QueueItem> items = jdbc.sql("""
                        SELECT q.id,q.provider,q.media_id,q.title,q.thumbnail_url,q.added_by,
                               u.display_name,q.personal_position,q.personal_queue_item,q.created_at,
                               COUNT(v.user_id) vote_count,BOOL_OR(v.user_id=:userId) voted
                        FROM room_watch_queue q
                        JOIN app_users u ON u.id=q.added_by
                        LEFT JOIN room_watch_votes v ON v.queue_id=q.id
                        WHERE q.room_id=:roomId AND q.status='QUEUED'
                        GROUP BY q.id,u.display_name
                        ORDER BY vote_count DESC,q.created_at,q.id
                        """)
                .param("roomId", roomId)
                .param("userId", currentUserId)
                .query((rs, row) -> new QueueItem(
                        rs.getObject("id", UUID.class),
                        rs.getString("provider"),
                        rs.getString("media_id"),
                        rs.getString("title"),
                        rs.getString("thumbnail_url"),
                        rs.getObject("added_by", UUID.class),
                        rs.getString("display_name"),
                        rs.getInt("personal_position"),
                        rs.getBoolean("personal_queue_item"),
                        rs.getInt("vote_count"),
                        rs.getBoolean("voted"),
                        List.of(),
                        rs.getTimestamp("created_at").toInstant()))
                .list();

        Map<UUID, List<QueuePicker>> pickersByQueueItem = new HashMap<>();
        jdbc.sql("""
                        SELECT q.id queue_id,u.id user_id,u.display_name,u.avatar_url
                        FROM room_watch_queue q
                        JOIN LATERAL (
                            SELECT q.added_by user_id
                            UNION
                            SELECT v.user_id FROM room_watch_votes v WHERE v.queue_id=q.id
                        ) selected ON true
                        JOIN app_users u ON u.id=selected.user_id
                        WHERE q.room_id=:roomId AND q.status='QUEUED'
                        ORDER BY q.id,CASE WHEN u.id=q.added_by THEN 0 ELSE 1 END,u.display_name
                        """)
                .param("roomId", roomId)
                .query((rs, row) -> new QueuePickerRow(
                        rs.getObject("queue_id", UUID.class),
                        new QueuePicker(
                                rs.getObject("user_id", UUID.class),
                                rs.getString("display_name"),
                                rs.getString("avatar_url"))))
                .list()
                .forEach(row -> pickersByQueueItem
                        .computeIfAbsent(row.queueId(), ignored -> new ArrayList<>())
                        .add(row.picker()));

        return items.stream()
                .map(item -> item.withPickers(pickersByQueueItem.getOrDefault(item.id(), List.of())))
                .toList();
    }

    public Optional<UUID> queuedItemId(UUID roomId, String provider, String mediaId) {
        return jdbc.sql("""
                        SELECT id FROM room_watch_queue
                        WHERE room_id=:roomId AND provider=:provider AND media_id=:mediaId
                          AND status='QUEUED'
                        ORDER BY created_at LIMIT 1
                        """)
                .param("roomId", roomId)
                .param("provider", provider)
                .param("mediaId", mediaId)
                .query(UUID.class)
                .optional();
    }

    public boolean isCurrentMedia(UUID roomId, String provider, String mediaId) {
        return jdbc.sql("""
                        SELECT EXISTS(
                            SELECT 1 FROM room_watch_state
                            WHERE room_id=:roomId AND provider=:provider AND media_id=:mediaId
                        )
                        """)
                .param("roomId", roomId)
                .param("provider", provider)
                .param("mediaId", mediaId)
                .query(Boolean.class)
                .single();
    }

    public int nextPersonalPosition(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT COALESCE(MAX(personal_position),-1)+1
                        FROM room_watch_queue
                        WHERE room_id=:roomId AND added_by=:userId AND status='QUEUED'
                          AND personal_queue_item
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(Integer.class)
                .single();
    }

    public boolean insert(
            UUID id,
            UUID roomId,
            String provider,
            String mediaId,
            String title,
            String thumbnailUrl,
            UUID userId,
            int position,
            boolean personalQueueItem) {
        return jdbc.sql("""
                        INSERT INTO room_watch_queue(
                            id,room_id,provider,media_id,title,thumbnail_url,added_by,
                            personal_position,personal_queue_item
                        ) VALUES(:id,:roomId,:provider,:mediaId,:title,:thumbnail,:userId,
                            :position,:personalQueueItem)
                        ON CONFLICT (room_id,provider,media_id) WHERE status='QUEUED' DO NOTHING
                        """)
                .param("id", id)
                .param("roomId", roomId)
                .param("provider", provider)
                .param("mediaId", mediaId)
                .param("title", title)
                .param("thumbnail", thumbnailUrl)
                .param("userId", userId)
                .param("position", position)
                .param("personalQueueItem", personalQueueItem)
                .update() == 1;
    }

    public void selectVote(UUID roomId, UUID userId, UUID queueId) {
        jdbc.sql("DELETE FROM room_watch_votes WHERE room_id=:roomId AND user_id=:userId")
                .param("roomId", roomId)
                .param("userId", userId)
                .update();
        jdbc.sql("""
                        INSERT INTO room_watch_votes(room_id,queue_id,user_id)
                        SELECT :roomId,id,:userId FROM room_watch_queue
                        WHERE id=:queueId AND room_id=:roomId AND status='QUEUED'
                        """)
                .param("roomId", roomId)
                .param("queueId", queueId)
                .param("userId", userId)
                .update();
    }

    public Set<UUID> ownedQueueIds(UUID roomId, UUID userId) {
        return new HashSet<>(jdbc.sql("""
                        SELECT id FROM room_watch_queue
                        WHERE room_id=:roomId AND added_by=:userId AND status='QUEUED'
                          AND personal_queue_item
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(UUID.class)
                .list());
    }

    public void updatePosition(UUID roomId, UUID userId, UUID queueId, int position) {
        jdbc.sql("""
                        UPDATE room_watch_queue SET personal_position=:position
                        WHERE id=:queueId AND room_id=:roomId AND added_by=:userId
                          AND personal_queue_item
                        """)
                .param("position", position)
                .param("queueId", queueId)
                .param("roomId", roomId)
                .param("userId", userId)
                .update();
    }

    public boolean queuedItemExists(UUID roomId, UUID queueId) {
        return jdbc.sql("""
                        SELECT EXISTS(SELECT 1 FROM room_watch_queue
                        WHERE id=:queueId AND room_id=:roomId AND status='QUEUED')
                        """)
                .param("queueId", queueId)
                .param("roomId", roomId)
                .query(Boolean.class)
                .single();
    }

    public boolean isRoomCandidate(UUID roomId, UUID queueId) {
        return jdbc.sql("""
                        SELECT EXISTS(
                            SELECT 1
                            FROM room_watch_queue q
                            WHERE q.id=:queueId AND q.room_id=:roomId AND q.status='QUEUED'
                              AND q.personal_position=(
                                  SELECT MIN(head.personal_position)
                                  FROM room_watch_queue head
                                  WHERE head.room_id=q.room_id
                                    AND head.added_by=q.added_by
                                    AND head.status='QUEUED'
                              )
                        )
                        """)
                .param("queueId", queueId)
                .param("roomId", roomId)
                .query(Boolean.class)
                .single();
    }

    public boolean hasVote(UUID queueId, UUID userId) {
        return jdbc.sql("""
                        SELECT EXISTS(SELECT 1 FROM room_watch_votes
                        WHERE queue_id=:queueId AND user_id=:userId)
                        """)
                .param("queueId", queueId)
                .param("userId", userId)
                .query(Boolean.class)
                .single();
    }

    public void deleteVote(UUID queueId, UUID userId) {
        jdbc.sql("DELETE FROM room_watch_votes WHERE queue_id=:queueId AND user_id=:userId")
                .param("queueId", queueId)
                .param("userId", userId)
                .update();
    }

    public void deleteQueueItem(UUID roomId, UUID queueId) {
        jdbc.sql("DELETE FROM room_watch_queue WHERE id=:queueId AND room_id=:roomId")
                .param("queueId", queueId)
                .param("roomId", roomId)
                .update();
    }

    public List<NextVideo> nextCandidates(UUID roomId) {
        return jdbc.sql("""
                        SELECT q.id,q.provider,q.media_id,q.title,q.added_by,q.created_at,
                               COUNT(v.user_id) votes
                        FROM room_watch_queue q
                        JOIN room_watch_votes v ON v.queue_id=q.id
                        WHERE q.room_id=:roomId AND q.status='QUEUED'
                        GROUP BY q.id,q.provider,q.media_id,q.title,q.added_by,q.created_at
                        ORDER BY votes DESC,q.created_at,q.id
                        """)
                .param("roomId", roomId)
                .query((rs, row) -> new NextVideo(
                        rs.getObject("id", UUID.class),
                        rs.getString("provider"),
                        rs.getString("media_id"),
                        rs.getString("title"),
                        rs.getObject("added_by", UUID.class),
                        rs.getTimestamp("created_at").toInstant(),
                        rs.getInt("votes")))
                .list();
    }

    public void markPlayed(UUID queueId) {
        jdbc.sql("UPDATE room_watch_queue SET status='PLAYED' WHERE id=:queueId")
                .param("queueId", queueId)
                .update();
    }

    public Optional<UUID> firstQueuedItemForUser(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT id FROM room_watch_queue
                        WHERE room_id=:roomId AND added_by=:userId AND status='QUEUED'
                          AND personal_queue_item
                        ORDER BY personal_position,created_at,id LIMIT 1
                        """)
                .param("roomId", roomId)
                .param("userId", userId)
                .query(UUID.class)
                .optional();
    }

    public Optional<String> currentMediaId(UUID roomId) {
        return jdbc.sql("SELECT media_id FROM room_watch_state WHERE room_id=:roomId")
                .param("roomId", roomId)
                .query(String.class)
                .optional();
    }

    public void addSkipVote(UUID roomId, String mediaId, UUID userId) {
        jdbc.sql("""
                        INSERT INTO room_watch_skip_votes(room_id,media_id,user_id)
                        VALUES(:roomId,:mediaId,:userId) ON CONFLICT DO NOTHING
                        """)
                .param("roomId", roomId)
                .param("mediaId", mediaId)
                .param("userId", userId)
                .update();
    }

    public SkipStatus skipStatus(UUID roomId, String mediaId, UUID userId) {
        int active = jdbc.sql("""
                        SELECT COUNT(*) FROM room_live_presence
                        WHERE room_id=:roomId AND last_seen_at>now()-interval '45 seconds'
                        """)
                .param("roomId", roomId)
                .query(Integer.class)
                .single();
        int required = Math.max(1, (active / 2) + 1);
        if (mediaId.isBlank()) return new SkipStatus(0, required, false);
        return jdbc.sql("""
                        SELECT COUNT(*) votes,BOOL_OR(user_id=:userId) voted
                        FROM room_watch_skip_votes
                        WHERE room_id=:roomId AND media_id=:mediaId
                        """)
                .param("userId", userId)
                .param("roomId", roomId)
                .param("mediaId", mediaId)
                .query((rs, row) -> new SkipStatus(
                        rs.getInt("votes"), required, rs.getBoolean("voted")))
                .single();
    }

    public void updateSettings(UUID roomId, String mode, int transitionSeconds) {
        jdbc.sql("""
                        UPDATE rooms
                        SET watch_queue_mode=:mode,watch_transition_seconds=:seconds
                        WHERE id=:roomId
                        """)
                .param("mode", mode)
                .param("seconds", transitionSeconds)
                .param("roomId", roomId)
                .update();
    }

    public void updateVideoPermission(UUID roomId, UUID userId, boolean allowed) {
        jdbc.sql("""
                        UPDATE room_members SET can_add_videos=:allowed
                        WHERE room_id=:roomId AND user_id=:userId AND role <> 'HOST'
                        """)
                .param("allowed", allowed)
                .param("roomId", roomId)
                .param("userId", userId)
                .update();
    }

    private record QueuePickerRow(UUID queueId, QueuePicker picker) {}
}
