package com.letscook.platform.room;

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

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/rooms/{roomId}/live")
public class LiveRoomController {
    private final JdbcClient jdbc;
    private final CurrentUserService users;
    public LiveRoomController(JdbcClient jdbc, CurrentUserService users) { this.jdbc=jdbc; this.users=users; }

    @PostMapping("/join")
    @Transactional
    void join(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt); requireMember(roomId,user.id()); cleanup(roomId);
        jdbc.sql("""
            INSERT INTO room_live_presence(room_id,user_id) VALUES(:room,:user)
            ON CONFLICT(room_id,user_id) DO UPDATE SET last_seen_at=now()
            """).param("room",roomId).param("user",user.id()).update();
        jdbc.sql("UPDATE rooms SET empty_since=NULL WHERE id=:room").param("room",roomId).update();
    }

    @PostMapping("/heartbeat")
    void heartbeat(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt);
        jdbc.sql("UPDATE room_live_presence SET last_seen_at=now() WHERE room_id=:room AND user_id=:user")
                .param("room",roomId).param("user",user.id()).update(); cleanup(roomId);
    }

    @DeleteMapping("/leave")
    @Transactional
    void leave(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt);
        jdbc.sql("DELETE FROM room_live_presence WHERE room_id=:room AND user_id=:user").param("room",roomId).param("user",user.id()).update();
        rebalanceLeadership(roomId);
        clearIfEmpty(roomId);
    }

    @GetMapping("/participants")
    List<Participant> participants(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt); requireMember(roomId,user.id()); cleanup(roomId);
        List<Participant> participants=jdbc.sql("""
            SELECT u.id,u.username,u.display_name,u.avatar_url,rm.role,rm.can_share_screen FROM room_live_presence p
            JOIN app_users u ON u.id=p.user_id JOIN room_members rm ON rm.room_id=p.room_id AND rm.user_id=p.user_id
            WHERE p.room_id=:room ORDER BY CASE rm.role WHEN 'HOST' THEN 0 WHEN 'CO_HOST' THEN 1 ELSE 2 END,u.display_name
            """).param("room",roomId).query((rs,n)->new Participant(rs.getObject("id",UUID.class),rs.getString("username"),
                rs.getString("display_name"),rs.getString("avatar_url"),RoomRole.valueOf(rs.getString("role")),
                rs.getBoolean("can_share_screen"))).list();
        jdbc.sql("""
            INSERT INTO user_recent_room_people(viewer_id,seen_user_id,room_id,last_seen_at)
            SELECT :viewer,p.user_id,:room,now() FROM room_live_presence p
            WHERE p.room_id=:room AND p.user_id<>:viewer
            ON CONFLICT(viewer_id,seen_user_id) DO UPDATE SET room_id=EXCLUDED.room_id,last_seen_at=now()
            """).param("viewer",user.id()).param("room",roomId).update();
        return participants;
    }

    @GetMapping("/recent-people")
    List<RecentPerson> recentPeople(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt); requireMember(roomId,user.id());
        return jdbc.sql("""
            SELECT u.id,u.username,u.display_name,u.avatar_url,r.name room_name,x.last_seen_at,
              EXISTS(SELECT 1 FROM friendships f WHERE ((f.requester_id=:viewer AND f.addressee_id=u.id) OR (f.addressee_id=:viewer AND f.requester_id=u.id)) AND f.status='ACCEPTED') friend
            FROM user_recent_room_people x JOIN app_users u ON u.id=x.seen_user_id JOIN rooms r ON r.id=x.room_id
            WHERE x.viewer_id=:viewer ORDER BY x.last_seen_at DESC LIMIT 50
            """).param("viewer",user.id()).query((rs,n)->new RecentPerson(rs.getObject("id",UUID.class),rs.getString("username"),
                rs.getString("display_name"),rs.getString("avatar_url"),rs.getString("room_name"),
                rs.getTimestamp("last_seen_at").toInstant(),rs.getBoolean("friend"))).list();
    }

    @GetMapping("/messages")
    List<ChatMessage> messages(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId) {
        CurrentUser user=users.synchronize(jwt); requirePresent(roomId,user.id()); cleanup(roomId);
        return jdbc.sql("""
            SELECT m.id,m.sender_id,u.display_name,u.avatar_url,m.body,m.created_at FROM room_session_messages m
            JOIN app_users u ON u.id=m.sender_id WHERE m.room_id=:room ORDER BY m.created_at DESC LIMIT 200
            """).param("room",roomId).query((rs,n)->new ChatMessage(rs.getObject("id",UUID.class),rs.getObject("sender_id",UUID.class),
                rs.getString("display_name"),rs.getString("avatar_url"),rs.getString("body"),rs.getTimestamp("created_at").toInstant())).list()
                .stream().collect(java.util.stream.Collectors.collectingAndThen(java.util.stream.Collectors.toList(), list->{Collections.reverse(list);return list;}));
    }

    @PostMapping("/messages")
    ChatMessage send(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@Valid @RequestBody SendChat input) {
        CurrentUser user=users.synchronize(jwt); requirePresent(roomId,user.id());
        UUID id=UUID.randomUUID(); Instant now=Instant.now(); String body=input.body().trim();
        jdbc.sql("INSERT INTO room_session_messages(id,room_id,sender_id,body,created_at) VALUES(:id,:room,:sender,:body,:at)")
                .param("id",id).param("room",roomId).param("sender",user.id()).param("body",body).param("at",Timestamp.from(now)).update();
        return new ChatMessage(id,user.id(),user.displayName(),null,body,now);
    }

    private void cleanup(UUID roomId) {
        jdbc.sql("DELETE FROM room_live_presence WHERE room_id=:room AND last_seen_at < now()-interval '45 seconds'").param("room",roomId).update();
        rebalanceLeadership(roomId);
        clearIfEmpty(roomId);
    }
    private void clearIfEmpty(UUID roomId) {
        boolean empty=jdbc.sql("SELECT NOT EXISTS(SELECT 1 FROM room_live_presence WHERE room_id=:room)").param("room",roomId).query(Boolean.class).single();
        if(empty) {
            boolean ephemeral=jdbc.sql("SELECT COALESCE((SELECT ephemeral FROM rooms WHERE id=:room),false)").param("room",roomId).query(Boolean.class).single();
            if(ephemeral)jdbc.sql("UPDATE rooms SET empty_since=COALESCE(empty_since,now()) WHERE id=:room").param("room",roomId).update();
            jdbc.sql("DELETE FROM room_session_messages WHERE room_id=:room").param("room",roomId).update();
        }
    }
    private void rebalanceLeadership(UUID roomId) {
        boolean hostPresent=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_live_presence p JOIN room_members m ON m.room_id=p.room_id AND m.user_id=p.user_id WHERE p.room_id=:r AND m.role='HOST')")
                .param("r",roomId).query(Boolean.class).single();
        if(hostPresent)return;
        UUID next=jdbc.sql("""
                SELECT p.user_id FROM room_live_presence p JOIN room_members m ON m.room_id=p.room_id AND m.user_id=p.user_id
                WHERE p.room_id=:r AND m.status='ACTIVE'
                ORDER BY CASE m.role WHEN 'CO_HOST' THEN 0 WHEN 'MODERATOR' THEN 1 ELSE 2 END,p.joined_at LIMIT 1
                """).param("r",roomId).query(UUID.class).optional().orElse(null);
        if(next==null)return;
        jdbc.sql("UPDATE room_members SET role='CO_HOST' WHERE room_id=:r AND role='HOST'").param("r",roomId).update();
        jdbc.sql("UPDATE room_members SET role='HOST',can_share_screen=true,can_add_videos=true WHERE room_id=:r AND user_id=:u")
                .param("r",roomId).param("u",next).update();
        jdbc.sql("UPDATE rooms SET owner_id=:u,updated_at=now() WHERE id=:r").param("u",next).param("r",roomId).update();
    }
    private void requireMember(UUID roomId,UUID userId) {
        boolean ok=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_members WHERE room_id=:room AND user_id=:user AND status='ACTIVE')")
                .param("room",roomId).param("user",userId).query(Boolean.class).single();
        if(!ok) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Active room membership required");
    }
    private void requirePresent(UUID roomId,UUID userId) {
        boolean ok=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_live_presence WHERE room_id=:room AND user_id=:user)")
                .param("room",roomId).param("user",userId).query(Boolean.class).single();
        if(!ok) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Join the live room before chatting");
    }
    public record Participant(UUID userId,String username,String displayName,String avatarUrl,RoomRole role,
                              boolean canShareScreen) {}
    public record ChatMessage(UUID id,UUID senderId,String senderName,String avatarUrl,String body,Instant createdAt) {}
    public record RecentPerson(UUID userId,String username,String displayName,String avatarUrl,String roomName,Instant lastSeenAt,boolean friend) {}
    public record SendChat(@NotBlank @Size(max=2000) String body) {}
}
