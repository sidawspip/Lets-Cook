package com.letscook.platform.search;

import static com.letscook.platform.search.SearchModels.*;

import com.letscook.platform.room.AccessPolicy;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Access-filtered PostgreSQL search for users and rooms visible to the requesting user.
 */
@Repository
public class SearchRepository {
    private final JdbcClient jdbc;

    public SearchRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<UserResult> users(UUID currentUserId, String term, String query) {
        return jdbc.sql("""
                        SELECT id, username, display_name, avatar_url
                        FROM app_users
                        WHERE id <> :currentUserId
                          AND (username ILIKE :term OR display_name ILIKE :term)
                        ORDER BY similarity(username, :query) DESC
                        LIMIT 20
                        """)
                .param("currentUserId", currentUserId)
                .param("term", term)
                .param("query", query)
                .query((rs, rowNum) -> new UserResult(
                        rs.getObject("id", UUID.class),
                        rs.getString("username"),
                        rs.getString("display_name"),
                        rs.getString("avatar_url")))
                .list();
    }

    public List<RoomResult> rooms(UUID currentUserId, String term, String query) {
        return jdbc.sql("""
                        SELECT r.id, r.name, r.description, r.access_policy, r.locked, r.visibility,
                               (SELECT count(*) FROM room_members x WHERE x.room_id = r.id AND x.status = 'ACTIVE') AS member_count
                        FROM rooms r
                        WHERE (r.name ILIKE :term OR r.description ILIKE :term)
                          AND NOT EXISTS(SELECT 1 FROM room_members banned WHERE banned.room_id=r.id AND banned.user_id=:currentUserId AND banned.status='BANNED')
                          AND (r.visibility = 'PUBLIC' OR (r.visibility = 'FRIENDS' AND EXISTS (
                              SELECT 1 FROM friendships f WHERE f.status='ACCEPTED' AND
                              ((f.requester_id=:currentUserId AND f.addressee_id=r.owner_id) OR
                               (f.addressee_id=:currentUserId AND f.requester_id=r.owner_id)))))
                          AND NOT EXISTS (SELECT 1 FROM room_members mine WHERE mine.room_id = r.id
                                          AND mine.user_id = :currentUserId AND mine.status = 'ACTIVE')
                        ORDER BY similarity(r.name, :query) DESC, r.updated_at DESC LIMIT 30
                        """)
                .param("currentUserId", currentUserId)
                .param("term", term)
                .param("query", query)
                .query((rs, rowNum) -> new RoomResult(
                        rs.getObject("id", UUID.class),
                        rs.getString("name"),
                        rs.getString("description"),
                        AccessPolicy.valueOf(rs.getString("access_policy")),
                        rs.getBoolean("locked"),
                        rs.getInt("member_count"),
                        rs.getString("visibility")))
                .list();
    }
}
