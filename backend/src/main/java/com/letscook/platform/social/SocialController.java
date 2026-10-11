package com.letscook.platform.social;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/social")
public class SocialController {
    private final JdbcClient jdbc;
    private final CurrentUserService users;

    public SocialController(JdbcClient jdbc, CurrentUserService users) { this.jdbc = jdbc; this.users = users; }

    @GetMapping("/friends")
    List<Friend> friends(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser me = users.synchronize(jwt);
        return jdbc.sql("""
            SELECT u.id, u.username, u.display_name, u.avatar_url, (u.last_seen_at > now() - interval '75 seconds') online
            FROM friendships f JOIN app_users u ON u.id = CASE WHEN f.requester_id = :me THEN f.addressee_id ELSE f.requester_id END
            WHERE (f.requester_id = :me OR f.addressee_id = :me) AND f.status = 'ACCEPTED'
            ORDER BY online DESC, u.display_name
            """).param("me", me.id()).query((rs,n) -> new Friend(rs.getObject("id", UUID.class), rs.getString("username"),
                rs.getString("display_name"), rs.getString("avatar_url"), rs.getBoolean("online"))).list();
    }

    @GetMapping("/friend-requests")
    List<FriendRequest> requests(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser me = users.synchronize(jwt);
        return jdbc.sql("""
            SELECT f.id, u.id user_id, u.username, u.display_name
            FROM friendships f JOIN app_users u ON u.id = f.requester_id
            WHERE f.addressee_id = :me AND f.status = 'PENDING' ORDER BY f.created_at
            """).param("me", me.id()).query((rs,n) -> new FriendRequest(rs.getObject("id", UUID.class),
                rs.getObject("user_id", UUID.class), rs.getString("username"), rs.getString("display_name"))).list();
    }

    @PostMapping("/friend-requests/{userId}")
    void request(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID userId) {
        CurrentUser me = users.synchronize(jwt);
        if (me.id().equals(userId)) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "You cannot friend yourself");
        try {
            jdbc.sql("INSERT INTO friendships (id, requester_id, addressee_id) VALUES (:id, :me, :them)")
                    .param("id", UUID.randomUUID()).param("me", me.id()).param("them", userId).update();
        } catch (RuntimeException ex) { throw new ResponseStatusException(HttpStatus.CONFLICT, "Friend request already exists"); }
    }

    @PostMapping("/friend-requests/{requestId}/{decision}")
    void decide(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID requestId, @PathVariable String decision) {
        CurrentUser me = users.synchronize(jwt);
        if (!decision.equals("accept") && !decision.equals("reject")) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid decision");
        int changed = decision.equals("accept")
                ? jdbc.sql("UPDATE friendships SET status='ACCEPTED', updated_at=now() WHERE id=:id AND addressee_id=:me AND status='PENDING'").param("id",requestId).param("me",me.id()).update()
                : jdbc.sql("DELETE FROM friendships WHERE id=:id AND addressee_id=:me AND status='PENDING'").param("id",requestId).param("me",me.id()).update();
        if (changed == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Friend request not found");
    }

    @GetMapping("/messages/{friendId}")
    @Transactional
    List<Message> messages(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID friendId) {
        CurrentUser me = users.synchronize(jwt); requireFriends(me.id(), friendId);
        List<Message> result = jdbc.sql("""
            SELECT id, sender_id, recipient_id, body, created_at FROM direct_messages
            WHERE (sender_id=:me AND recipient_id=:friend) OR (sender_id=:friend AND recipient_id=:me)
            ORDER BY created_at DESC LIMIT 100
            """).param("me",me.id()).param("friend",friendId)
                .query((rs,n) -> new Message(rs.getObject("id",UUID.class), rs.getObject("sender_id",UUID.class),
                        rs.getObject("recipient_id",UUID.class), rs.getString("body"), rs.getTimestamp("created_at").toInstant())).list();
        jdbc.sql("UPDATE direct_messages SET read_at=now() WHERE sender_id=:friend AND recipient_id=:me AND read_at IS NULL")
                .param("friend",friendId).param("me",me.id()).update();
        java.util.Collections.reverse(result); return result;
    }

    @PostMapping("/messages/{friendId}")
    Message send(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID friendId, @Valid @RequestBody SendMessage input) {
        CurrentUser me = users.synchronize(jwt); requireFriends(me.id(), friendId);
        UUID id=UUID.randomUUID(); Instant now=Instant.now(); String body=input.body().trim();
        jdbc.sql("INSERT INTO direct_messages (id,sender_id,recipient_id,body,created_at) VALUES (:id,:me,:friend,:body,:now)")
                .param("id",id).param("me",me.id()).param("friend",friendId).param("body",body)
                .param("now", java.sql.Timestamp.from(now)).update();
        return new Message(id,me.id(),friendId,body,now);
    }

    private void requireFriends(UUID a, UUID b) {
        boolean ok=jdbc.sql("SELECT EXISTS(SELECT 1 FROM friendships WHERE status='ACCEPTED' AND ((requester_id=:a AND addressee_id=:b) OR (requester_id=:b AND addressee_id=:a)))")
                .param("a",a).param("b",b).query(Boolean.class).single();
        if(!ok) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Direct messages are available to friends only");
    }

    public record Friend(UUID id,String username,String displayName,String avatarUrl,boolean online) {}
    public record FriendRequest(UUID id,UUID userId,String username,String displayName) {}
    public record Message(UUID id,UUID senderId,UUID recipientId,String body,Instant createdAt) {}
    public record SendMessage(@NotBlank @Size(max=2000) String body) {}
}
