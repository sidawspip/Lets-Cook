package com.letscook.platform.room;

import static com.letscook.platform.room.WatchModels.*;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Persistence for revisioned playback state, processed command IDs, room roles, and heartbeats.
 */
@Repository
public class WatchRepository {
    private final JdbcClient jdbc;

    public WatchRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<WatchState> state(UUID roomId) {
        return jdbc.sql("""
                        SELECT w.provider,w.source_type,w.source_url,w.media_id,w.title,w.playing,
                          w.position_seconds,w.duration_seconds,w.playback_rate,w.revision,w.updated_at,
                          w.transition_until,
                          (SELECT q.thumbnail_url FROM room_watch_queue q
                           WHERE q.room_id=w.room_id AND q.provider=w.provider AND q.media_id=w.media_id
                           ORDER BY q.created_at DESC LIMIT 1) thumbnail_url
                        FROM room_watch_state w WHERE w.room_id=:room
                        """)
                .param("room", roomId)
                .query((rs, row) -> {
                    boolean playing = rs.getBoolean("playing");
                    double rate = rs.getDouble("playback_rate");
                    double position = rs.getDouble("position_seconds");
                    Instant updatedAt = rs.getTimestamp("updated_at").toInstant();
                    Instant transition = rs.getTimestamp("transition_until") == null
                            ? null : rs.getTimestamp("transition_until").toInstant();
                    Instant start = transition != null && transition.isAfter(updatedAt) ? transition : updatedAt;
                    if (playing && Instant.now().isAfter(start)) {
                        position += Math.max(0, (Instant.now().toEpochMilli() - start.toEpochMilli()) / 1000d) * rate;
                    }
                    return new WatchState(
                            roomId, rs.getString("provider"), rs.getString("source_type"),
                            rs.getString("media_id"), rs.getString("source_url"),
                            rs.getString("thumbnail_url"), rs.getString("title"), playing, position,
                            (Double) rs.getObject("duration_seconds"), rate, rs.getLong("revision"),
                            updatedAt, Instant.now(), transition);
                })
                .optional();
    }

    public void save(
            UUID roomId, UUID userId, String provider, String sourceType, String mediaId,
            String sourceUrl, String title, boolean playing, double position, Double duration,
            double rate, Instant transition) {
        jdbc.sql("""
                        INSERT INTO room_watch_state(
                          room_id,provider,source_type,source_url,media_id,title,playing,
                          position_seconds,duration_seconds,playback_rate,revision,updated_at,updated_by,transition_until)
                        VALUES(:room,:provider,:sourceType,:sourceUrl,:mediaId,:title,:playing,
                          :position,:duration,:rate,1,now(),:user,CAST(:transition AS TIMESTAMPTZ))
                        ON CONFLICT(room_id) DO UPDATE SET
                          provider=EXCLUDED.provider,source_type=EXCLUDED.source_type,
                          source_url=EXCLUDED.source_url,media_id=EXCLUDED.media_id,title=EXCLUDED.title,
                          playing=EXCLUDED.playing,position_seconds=EXCLUDED.position_seconds,
                          duration_seconds=EXCLUDED.duration_seconds,playback_rate=EXCLUDED.playback_rate,
                          revision=room_watch_state.revision+1,updated_at=now(),updated_by=EXCLUDED.updated_by,
                          transition_until=EXCLUDED.transition_until
                        """)
                .param("room", roomId).param("provider", provider)
                .param("sourceType", sourceType == null ? provider : sourceType)
                .param("sourceUrl", sourceUrl).param("mediaId", mediaId).param("title", title)
                .param("playing", playing).param("position", Math.max(0, position))
                .param("duration", duration).param("rate", rate <= 0 ? 1 : rate)
                .param("user", userId).param("transition", transition == null ? null : transition.toString())
                .update();
    }

    public Optional<Long> commandRevision(UUID roomId, UUID commandId) {
        return jdbc.sql("SELECT state_revision FROM room_watch_commands WHERE room_id=:room AND command_id=:command")
                .param("room", roomId).param("command", commandId).query(Long.class).optional();
    }

    public void saveCommand(UUID roomId, UUID commandId, long revision) {
        jdbc.sql("""
                        INSERT INTO room_watch_commands(room_id,command_id,state_revision)
                        VALUES(:room,:command,:revision)
                        """)
                .param("room", roomId).param("command", commandId).param("revision", revision).update();
    }

    public void heartbeat(UUID roomId) {
        jdbc.sql("""
                        UPDATE room_watch_state SET position_seconds=position_seconds+
                          CASE WHEN playing AND (transition_until IS NULL OR transition_until<=now())
                          THEN EXTRACT(EPOCH FROM (now()-GREATEST(updated_at,COALESCE(transition_until,updated_at))))*playback_rate
                          ELSE 0 END, updated_at=now() WHERE room_id=:room
                        """)
                .param("room", roomId).update();
    }

    public void stop(UUID roomId, UUID userId) {
        jdbc.sql("""
                        UPDATE room_watch_state SET playing=false,updated_at=now(),updated_by=:user,
                          transition_until=NULL WHERE room_id=:room
                        """)
                .param("user", userId).param("room", roomId).update();
    }

    public Optional<String> role(UUID roomId, UUID userId) {
        return jdbc.sql("""
                        SELECT role FROM room_members
                        WHERE room_id=:room AND user_id=:user AND status='ACTIVE'
                        """)
                .param("room", roomId).param("user", userId).query(String.class).optional();
    }

    public void requestVideoAccess(UUID roomId, UUID userId) {
        int changed = jdbc.sql("""
                        UPDATE room_members SET video_access_requested=true
                        WHERE room_id=:room AND user_id=:user AND status='ACTIVE'
                          AND role NOT IN ('HOST','CO_HOST') AND can_view_video=false
                        """)
                .param("room", roomId).param("user", userId).update();
        if (changed == 0 && role(roomId, userId).isEmpty()) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.FORBIDDEN, "Active room membership is required");
        }
    }

    public void setVideoAccess(UUID roomId, UUID userId, boolean allowed) {
        int changed = jdbc.sql("""
                        UPDATE room_members
                        SET can_view_video=:allowed,video_access_requested=false
                        WHERE room_id=:room AND user_id=:user AND status='ACTIVE' AND role<>'HOST'
                        """)
                .param("allowed", allowed).param("room", roomId).param("user", userId).update();
        if (changed == 0) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.NOT_FOUND, "Member not found or is the owner");
        }
    }
}
