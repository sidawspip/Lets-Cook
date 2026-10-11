package com.letscook.platform.search;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.constraints.Size;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;
import com.letscook.platform.room.AccessPolicy;

@Validated
@RestController
@RequestMapping("/api/search")
public class SearchController {
    private final JdbcClient jdbc;
    private final CurrentUserService currentUserService;

    public SearchController(JdbcClient jdbc, CurrentUserService currentUserService) {
        this.jdbc = jdbc;
        this.currentUserService = currentUserService;
    }

    @GetMapping
    SearchResult search(@AuthenticationPrincipal Jwt jwt,
                        @RequestParam @Size(min = 2, max = 80) String q) {
        CurrentUser currentUser = currentUserService.synchronize(jwt);
        String term = "%" + q.trim() + "%";
        List<UserResult> users = jdbc.sql("""
                        SELECT id, username, display_name, avatar_url
                        FROM app_users
                        WHERE id <> :currentUserId
                          AND (username ILIKE :term OR display_name ILIKE :term)
                        ORDER BY similarity(username, :query) DESC
                        LIMIT 20
                        """)
                .param("currentUserId", currentUser.id())
                .param("term", term)
                .param("query", q.trim())
                .query((rs, rowNum) -> new UserResult(
                        rs.getObject("id", UUID.class),
                        rs.getString("username"),
                        rs.getString("display_name"),
                        rs.getString("avatar_url")))
                .list();
        List<RoomResult> rooms = jdbc.sql("""
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
                .param("currentUserId", currentUser.id()).param("term", term).param("query", q.trim())
                .query((rs, rowNum) -> new RoomResult(rs.getObject("id", UUID.class), rs.getString("name"),
                        rs.getString("description"), AccessPolicy.valueOf(rs.getString("access_policy")),
                        rs.getBoolean("locked"), rs.getInt("member_count"), rs.getString("visibility"))).list();
        return new SearchResult(users, rooms, List.of());
    }

    public record SearchResult(List<UserResult> users, List<RoomResult> rooms, List<Object> messages) {
    }

    public record UserResult(UUID id, String username, String displayName, String avatarUrl) {
    }

    public record RoomResult(UUID id, String name, String description, AccessPolicy accessPolicy,
                             boolean locked, int memberCount, String visibility) {
    }
}
