package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.room.RoomDtos.AccessResult;
import com.letscook.platform.room.RoomDtos.CreateInviteRequest;
import com.letscook.platform.room.RoomDtos.CreateRoomRequest;
import com.letscook.platform.room.RoomDtos.InviteCreated;
import com.letscook.platform.room.RoomDtos.RoomCreated;
import com.letscook.platform.room.RoomDtos.RoomSummary;
import org.springframework.http.HttpStatus;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import io.livekit.server.AccessToken;
import io.livekit.server.CanPublish;
import io.livekit.server.CanPublishData;
import io.livekit.server.CanPublishSources;
import io.livekit.server.CanSubscribe;
import io.livekit.server.RoomJoin;
import io.livekit.server.RoomName;
import com.letscook.platform.room.RoomDtos.MediaToken;

@Service
public class RoomService {
    private static final Logger log = LoggerFactory.getLogger(RoomService.class);
    private final JdbcClient jdbc;
    private final PasswordEncoder passwordEncoder;
    private final String liveKitUrl;
    private final String liveKitApiKey;
    private final String liveKitApiSecret;
    private final SecureRandom random = new SecureRandom();

    public RoomService(
            JdbcClient jdbc,
            PasswordEncoder passwordEncoder,
            @Value("${app.livekit.url}") String liveKitUrl,
            @Value("${app.livekit.api-key}") String liveKitApiKey,
            @Value("${app.livekit.api-secret}") String liveKitApiSecret) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.liveKitUrl = liveKitUrl;
        this.liveKitApiKey = liveKitApiKey;
        this.liveKitApiSecret = liveKitApiSecret;
    }

    public List<RoomSummary> listFor(CurrentUser user) {
        deleteExpiredParties();
        return jdbc.sql("""
                        SELECT r.id, r.name, r.description, r.access_policy, rm.role, r.locked, r.visibility, r.screen_share_policy,
                               (SELECT count(*) FROM room_members x WHERE x.room_id = r.id AND x.status = 'ACTIVE') AS member_count,
                               (SELECT count(*) FROM room_members x WHERE x.room_id = r.id AND x.status = 'PENDING') AS pending_count
                        FROM rooms r
                        JOIN room_members rm ON rm.room_id = r.id
                        WHERE rm.user_id = :userId AND rm.status = 'ACTIVE'
                          AND (NOT r.ephemeral OR EXISTS(SELECT 1 FROM room_live_presence p WHERE p.room_id=r.id AND p.last_seen_at>now()-interval '45 seconds'))
                        ORDER BY r.updated_at DESC
                        """)
                .param("userId", user.id())
                .query((rs, rowNum) -> new RoomSummary(
                        rs.getObject("id", UUID.class),
                        rs.getString("name"),
                        rs.getString("description"),
                        AccessPolicy.valueOf(rs.getString("access_policy")),
                        RoomRole.valueOf(rs.getString("role")),
                        rs.getBoolean("locked"),
                        rs.getInt("member_count"), rs.getInt("pending_count"), rs.getString("visibility"), rs.getString("screen_share_policy")))
                .list();
    }

    @Transactional
    public RoomCreated create(CurrentUser owner, CreateRoomRequest request) {
        boolean nameTaken = jdbc.sql("SELECT EXISTS (SELECT 1 FROM rooms WHERE lower(btrim(name)) = lower(btrim(:name)))")
                .param("name", request.name()).query(Boolean.class).single();
        if (nameTaken) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "That room name is already taken");
        }
        UUID roomId = UUID.randomUUID();
        String accessKey = request.accessPolicy().usesKey() ? generateSecret() : null;
        String verifier = accessKey == null ? null : passwordEncoder.encode(accessKey);
        int maxMembers = request.maxMembers() == 0 ? 25 : request.maxMembers();

        jdbc.sql("""
                        INSERT INTO rooms (id, name, description, owner_id, access_policy, key_verifier, approval_required, max_members, visibility, ephemeral, empty_since)
                        VALUES (:id, :name, :description, :ownerId, :policy, :verifier, :approvalRequired, :maxMembers, :visibility, :ephemeral, CASE WHEN :ephemeral THEN now() ELSE NULL END)
                        """)
                .param("id", roomId)
                .param("name", request.name().trim())
                .param("description", request.description())
                .param("ownerId", owner.id())
                .param("policy", request.accessPolicy().name())
                .param("verifier", verifier)
                .param("approvalRequired", request.approvalRequired())
                .param("maxMembers", maxMembers)
                .param("visibility", validVisibility(request.visibility()))
                .param("ephemeral", Boolean.TRUE.equals(request.ephemeral()))
                .update();

        jdbc.sql("INSERT INTO room_members (room_id, user_id, role, can_share_screen) VALUES (:roomId, :userId, 'HOST', true)")
                .param("roomId", roomId)
                .param("userId", owner.id())
                .update();

        RoomSummary room = new RoomSummary(roomId, request.name().trim(), request.description(),
                request.accessPolicy(), RoomRole.HOST, false, 1, 0, validVisibility(request.visibility()), "HOSTS_ONLY");
        return new RoomCreated(room, accessKey);
    }

    @Transactional
    public void delete(CurrentUser actor, UUID roomId) {
        UUID ownerId = jdbc.sql("SELECT owner_id FROM rooms WHERE id = :roomId")
                .param("roomId", roomId).query(UUID.class).optional()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Room not found"));
        if (!ownerId.equals(actor.id())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only the room owner can delete this room");
        }
        jdbc.sql("DELETE FROM rooms WHERE id = :roomId").param("roomId", roomId).update();
    }

    public List<RoomDtos.JoinRequest> joinRequests(CurrentUser actor, UUID roomId) {
        requireRoomManager(actor, roomId);
        return jdbc.sql("""
                        SELECT u.id, u.username, u.display_name, u.avatar_url
                        FROM room_members rm JOIN app_users u ON u.id = rm.user_id
                        WHERE rm.room_id = :roomId AND rm.status = 'PENDING' ORDER BY rm.joined_at
                        """).param("roomId", roomId)
                .query((rs, n) -> new RoomDtos.JoinRequest(rs.getObject("id", UUID.class), rs.getString("username"),
                        rs.getString("display_name"), rs.getString("avatar_url"))).list();
    }

    @Transactional
    public void decideJoinRequest(CurrentUser actor, UUID roomId, UUID userId, boolean approve) {
        requireRoomManager(actor, roomId);
        int changed = approve
                ? jdbc.sql("UPDATE room_members SET status = 'ACTIVE' WHERE room_id = :roomId AND user_id = :userId AND status = 'PENDING'")
                    .param("roomId", roomId).param("userId", userId).update()
                : jdbc.sql("DELETE FROM room_members WHERE room_id = :roomId AND user_id = :userId AND status = 'PENDING'")
                    .param("roomId", roomId).param("userId", userId).update();
        if (changed == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Pending request not found");
    }

    public List<RoomDtos.RoomMember> members(CurrentUser actor, UUID roomId) {
        requireRoomManager(actor, roomId);
        return jdbc.sql("""
                        SELECT u.id, u.username, u.display_name, rm.role, rm.can_share_screen, rm.can_add_videos,
                               (u.last_seen_at > now() - interval '75 seconds') online
                        FROM room_members rm JOIN app_users u ON u.id = rm.user_id
                        WHERE rm.room_id = :roomId AND rm.status = 'ACTIVE'
                        ORDER BY CASE rm.role WHEN 'HOST' THEN 0 WHEN 'CO_HOST' THEN 1 ELSE 2 END, u.display_name
                        """).param("roomId", roomId)
                .query((rs,n) -> new RoomDtos.RoomMember(rs.getObject("id",UUID.class), rs.getString("username"),
                        rs.getString("display_name"), RoomRole.valueOf(rs.getString("role")),
                        rs.getBoolean("can_share_screen"), rs.getBoolean("can_add_videos"), rs.getBoolean("online"))).list();
    }

    @Transactional
    public void setScreenPermission(CurrentUser actor, UUID roomId, UUID userId, boolean allowed) {
        requireRoomOwner(actor, roomId);
        int changed = jdbc.sql("UPDATE room_members SET can_share_screen=:allowed WHERE room_id=:roomId AND user_id=:userId AND role <> 'HOST'")
                .param("allowed",allowed).param("roomId",roomId).param("userId",userId).update();
        if(changed==0) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Member not found or is the owner");
    }

    @Transactional
    public void kickMember(CurrentUser actor, UUID roomId, UUID userId) {
        requireRoomOwner(actor, roomId);
        if (actor.id().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "The room owner cannot be kicked");
        }
        jdbc.sql("DELETE FROM room_live_presence WHERE room_id=:roomId AND user_id=:userId")
                .param("roomId", roomId).param("userId", userId).update();
        int changed = jdbc.sql("UPDATE room_members SET status='BANNED' WHERE room_id=:roomId AND user_id=:userId AND role <> 'HOST'")
                .param("roomId", roomId).param("userId", userId).update();
        if (changed == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Member not found or is the room owner");
        }
    }

    @Transactional
    public void inviteUser(CurrentUser actor,UUID roomId,UUID userId) {
        boolean member=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_members WHERE room_id=:r AND user_id=:u AND status='ACTIVE')")
                .param("r",roomId).param("u",actor.id()).query(Boolean.class).single();
        if(!member)throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Only room members can invite people");
        jdbc.sql("""
                INSERT INTO room_members(room_id,user_id,role,status,invited_by) VALUES(:r,:u,'MEMBER','ACTIVE',:by)
                ON CONFLICT(room_id,user_id) DO UPDATE SET status='ACTIVE',role=CASE WHEN room_members.role='HOST' THEN 'HOST' ELSE 'MEMBER' END,invited_by=:by
                """).param("r",roomId).param("u",userId).param("by",actor.id()).update();
    }

    @Transactional
    public void setLeadership(CurrentUser actor,UUID roomId,UUID userId,String action) {
        requireRoomOwner(actor,roomId);
        String targetRole=jdbc.sql("SELECT role FROM room_members WHERE room_id=:r AND user_id=:u AND status='ACTIVE'")
                .param("r",roomId).param("u",userId).query(String.class).optional()
                .orElseThrow(()->new ResponseStatusException(HttpStatus.NOT_FOUND,"Member not found"));
        if("TRANSFER".equals(action)) {
            if("HOST".equals(targetRole))return;
            int cohosts=jdbc.sql("SELECT count(*) FROM room_members WHERE room_id=:r AND role='CO_HOST' AND status='ACTIVE'").param("r",roomId).query(Integer.class).single();
            jdbc.sql("UPDATE room_members SET role=:role,can_share_screen=true,can_add_videos=true WHERE room_id=:r AND user_id=:u")
                    .param("role",cohosts>=3?"MEMBER":"CO_HOST").param("r",roomId).param("u",actor.id()).update();
            jdbc.sql("UPDATE room_members SET role='HOST',can_share_screen=true,can_add_videos=true WHERE room_id=:r AND user_id=:u")
                    .param("r",roomId).param("u",userId).update();
            jdbc.sql("UPDATE rooms SET owner_id=:u,updated_at=now() WHERE id=:r").param("u",userId).param("r",roomId).update();
            return;
        }
        if("CO_HOST".equals(action)) {
            int count=jdbc.sql("SELECT count(*) FROM room_members WHERE room_id=:r AND role='CO_HOST' AND status='ACTIVE'").param("r",roomId).query(Integer.class).single();
            if(count>=3&&!"CO_HOST".equals(targetRole))throw new ResponseStatusException(HttpStatus.CONFLICT,"A room can have at most 3 co-hosts");
            jdbc.sql("UPDATE room_members SET role='CO_HOST',can_share_screen=true,can_add_videos=true WHERE room_id=:r AND user_id=:u AND role<>'HOST'")
                    .param("r",roomId).param("u",userId).update();return;
        }
        if("MEMBER".equals(action)) {
            jdbc.sql("UPDATE room_members SET role='MEMBER' WHERE room_id=:r AND user_id=:u AND role='CO_HOST'")
                    .param("r",roomId).param("u",userId).update();return;
        }
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid leadership action");
    }

    public List<RoomDtos.PublicRoom> publicLive(CurrentUser user) {
        deleteExpiredParties();
        return jdbc.sql("""
                SELECT r.id,r.name,r.description,r.access_policy,
                  (SELECT count(*) FROM room_live_presence p WHERE p.room_id=r.id AND p.last_seen_at>now()-interval '45 seconds') viewers,
                  w.title,w.media_id,EXISTS(SELECT 1 FROM room_members m WHERE m.room_id=r.id AND m.user_id=:u AND m.status='ACTIVE') joined
                FROM rooms r LEFT JOIN room_watch_state w ON w.room_id=r.id
                WHERE EXISTS(SELECT 1 FROM room_live_presence p WHERE p.room_id=r.id AND p.last_seen_at>now()-interval '45 seconds')
                  AND NOT EXISTS(SELECT 1 FROM room_members ban WHERE ban.room_id=r.id AND ban.user_id=:u AND ban.status='BANNED')
                  AND (r.visibility='PUBLIC' OR (r.visibility='FRIENDS' AND EXISTS(SELECT 1 FROM friendships f WHERE f.status='ACCEPTED' AND ((f.requester_id=:u AND f.addressee_id=r.owner_id) OR (f.addressee_id=:u AND f.requester_id=r.owner_id)))) OR EXISTS(SELECT 1 FROM room_members mine WHERE mine.room_id=r.id AND mine.user_id=:u AND mine.status='ACTIVE'))
                ORDER BY viewers DESC,r.updated_at DESC LIMIT 60
                """).param("u",user.id()).query((rs,n)->{
                    UUID id=rs.getObject("id",UUID.class);
                    List<String> avatars=jdbc.sql("SELECT u.avatar_url FROM room_live_presence p JOIN app_users u ON u.id=p.user_id WHERE p.room_id=:r AND p.last_seen_at>now()-interval '45 seconds' AND u.avatar_url IS NOT NULL ORDER BY p.joined_at LIMIT 5")
                            .param("r",id).query(String.class).list();
                    return new RoomDtos.PublicRoom(id,rs.getString("name"),rs.getString("description"),AccessPolicy.valueOf(rs.getString("access_policy")),rs.getInt("viewers"),rs.getString("title"),rs.getString("media_id"),avatars,rs.getBoolean("joined"));
                }).list();
    }

    @Scheduled(fixedDelayString = "PT5M")
    public void deleteExpiredParties(){
        jdbc.sql("DELETE FROM rooms WHERE ephemeral=true AND empty_since IS NOT NULL AND empty_since<now()-interval '12 hours'").update();
    }

    @Transactional
    public void updateSettings(CurrentUser actor, UUID roomId, RoomDtos.UpdateRoomSettings input) {
        requireRoomOwner(actor, roomId);
        String visibility=validVisibility(input.visibility());
        String sharing=validSharePolicy(input.screenSharePolicy());
        String name=input.name()==null ? jdbc.sql("SELECT name FROM rooms WHERE id=:id").param("id",roomId).query(String.class).single() : input.name().trim();
        boolean taken=jdbc.sql("SELECT EXISTS(SELECT 1 FROM rooms WHERE id<>:id AND lower(btrim(name))=lower(btrim(:name)))")
                .param("id",roomId).param("name",name).query(Boolean.class).single();
        if(taken) throw new ResponseStatusException(HttpStatus.CONFLICT,"That room name is already taken");
        jdbc.sql("""
                UPDATE rooms SET name=:name, description=COALESCE(:description,description), visibility=:visibility,
                  access_policy=COALESCE(:policy,access_policy), approval_required=COALESCE(:approval,approval_required),
                  screen_share_policy=:sharing, updated_at=now() WHERE id=:id
                """).param("name",name).param("description",input.description()).param("visibility",visibility)
                .param("policy",input.accessPolicy()==null?null:input.accessPolicy().name()).param("approval",input.approvalRequired())
                .param("sharing",sharing).param("id",roomId).update();
    }

    private void requireRoomOwner(CurrentUser actor, UUID roomId) {
        UUID owner=jdbc.sql("SELECT owner_id FROM rooms WHERE id=:id").param("id",roomId).query(UUID.class).optional()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,"Room not found"));
        if(!owner.equals(actor.id())) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Only the room owner can change this setting");
    }

    private String validVisibility(String value) {
        String result=value==null?"PUBLIC":value.toUpperCase();
        if(!List.of("PUBLIC","PRIVATE","FRIENDS").contains(result)) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid visibility");
        return result;
    }

    private String validSharePolicy(String value) {
        String result=value==null?"HOSTS_ONLY":value.toUpperCase();
        if(!List.of("HOSTS_ONLY","EVERYONE","SELECTED").contains(result)) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid screen sharing policy");
        return result;
    }

    private void requireRoomManager(CurrentUser actor, UUID roomId) {
        String role = jdbc.sql("SELECT role FROM room_members WHERE room_id = :roomId AND user_id = :userId AND status = 'ACTIVE'")
                .param("roomId", roomId).param("userId", actor.id()).query(String.class).optional()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN, "Room manager access required"));
        if (!role.equals("HOST") && !role.equals("CO_HOST"))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Room manager access required");
    }

    @Transactional
    public AccessResult unlock(CurrentUser user, UUID roomId, String accessKey) {
        RoomAccess access = jdbc.sql("""
                        SELECT access_policy, key_verifier, locked, approval_required, max_members, visibility, owner_id
                        FROM rooms WHERE id = :id
                        """)
                .param("id", roomId)
                .query((rs, rowNum) -> new RoomAccess(
                        AccessPolicy.valueOf(rs.getString("access_policy")),
                        rs.getString("key_verifier"),
                        rs.getBoolean("locked"),
                        rs.getBoolean("approval_required"),
                        rs.getInt("max_members"),rs.getString("visibility"),rs.getObject("owner_id",UUID.class)))
                .optional()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Room not found"));

        if (access.locked()) {
            throw new ResponseStatusException(HttpStatus.LOCKED, "Room is locked");
        }
        String existing=jdbc.sql("SELECT status FROM room_members WHERE room_id=:r AND user_id=:u").param("r",roomId).param("u",user.id()).query(String.class).optional().orElse(null);
        if("BANNED".equals(existing))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"The room leader removed you from this room");
        if("ACTIVE".equals(existing))return new AccessResult(roomId,true,RoomRole.MEMBER,"ACTIVE");
        if (access.policy() == AccessPolicy.INVITE_ONLY || access.policy() == AccessPolicy.INVITE_AND_KEY) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "An invitation is required for this room");
        }
        if (access.policy().usesKey()
                && (accessKey == null || access.keyVerifier() == null
                || !passwordEncoder.matches(accessKey, access.keyVerifier()))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "The room key is incorrect");
        }
        boolean leaderFriend=jdbc.sql("SELECT EXISTS(SELECT 1 FROM friendships f WHERE f.status='ACCEPTED' AND ((f.requester_id=:u AND f.addressee_id=:o) OR (f.addressee_id=:u AND f.requester_id=:o)))")
                .param("u",user.id()).param("o",access.ownerId()).query(Boolean.class).single();
        if(!"PUBLIC".equals(access.visibility())&&!("FRIENDS".equals(access.visibility())&&leaderFriend))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"This room is invite only");
        Integer memberCount = jdbc.sql("SELECT count(*) FROM room_members WHERE room_id = :roomId AND status = 'ACTIVE'")
                .param("roomId", roomId).query(Integer.class).single();
        if (memberCount >= access.maxMembers()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Room is full");
        }

        String membershipStatus = access.approvalRequired() ? "PENDING" : "ACTIVE";
        jdbc.sql("""
                        INSERT INTO room_members (room_id, user_id, role, status)
                        VALUES (:roomId, :userId, 'MEMBER', :status)
                        ON CONFLICT (room_id, user_id) DO UPDATE SET status = EXCLUDED.status
                        """)
                .param("roomId", roomId)
                .param("userId", user.id())
                .param("status", membershipStatus)
                .update();
        return new AccessResult(roomId, "ACTIVE".equals(membershipStatus), RoomRole.MEMBER, membershipStatus);
    }

    @Transactional
    public InviteCreated createInvite(CurrentUser actor, UUID roomId, CreateInviteRequest request) {
        String role = jdbc.sql("SELECT role FROM room_members WHERE room_id = :roomId AND user_id = :userId AND status = 'ACTIVE'")
                .param("roomId", roomId)
                .param("userId", actor.id())
                .query(String.class)
                .optional()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.FORBIDDEN, "You are not a room member"));
        if (!role.equals("HOST") && !role.equals("CO_HOST")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only hosts and co-hosts can create invites");
        }
        if (request.role() == RoomRole.HOST || request.role() == RoomRole.CO_HOST) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invites cannot grant host roles");
        }

        String code = generateSecret();
        jdbc.sql("""
                        INSERT INTO room_invites (id, room_id, created_by, code, role_granted, expires_at, max_uses)
                        VALUES (:id, :roomId, :createdBy, :code, :role, :expiresAt, :maxUses)
                        """)
                .param("id", UUID.randomUUID())
                .param("roomId", roomId)
                .param("createdBy", actor.id())
                .param("code", code)
                .param("role", request.role().name())
                .param("expiresAt", request.expiresAt())
                .param("maxUses", request.maxUses())
                .update();
        return new InviteCreated(code, "/invite/" + code, request.expiresAt(), request.maxUses());
    }

    @Transactional
    public AccessResult acceptInvite(CurrentUser user, String code, String accessKey) {
        InviteAccess invite = jdbc.sql("""
                        SELECT i.id, i.room_id, i.role_granted, i.expires_at, i.max_uses, i.used_count, i.revoked,
                               r.access_policy, r.key_verifier, r.locked, r.approval_required, r.max_members
                        FROM room_invites i JOIN rooms r ON r.id = i.room_id WHERE i.code = :code
                        """)
                .param("code", code)
                .query((rs, rowNum) -> new InviteAccess(
                        rs.getObject("id", UUID.class), rs.getObject("room_id", UUID.class),
                        RoomRole.valueOf(rs.getString("role_granted")),
                        rs.getTimestamp("expires_at") == null ? null : rs.getTimestamp("expires_at").toInstant(),
                        (Integer) rs.getObject("max_uses"), rs.getInt("used_count"), rs.getBoolean("revoked"),
                        AccessPolicy.valueOf(rs.getString("access_policy")), rs.getString("key_verifier"),
                        rs.getBoolean("locked"), rs.getBoolean("approval_required"), rs.getInt("max_members")))
                .optional().orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Invite not found"));

        if (invite.revoked() || (invite.expiresAt() != null && invite.expiresAt().isBefore(Instant.now()))
                || (invite.maxUses() != null && invite.usedCount() >= invite.maxUses())) {
            throw new ResponseStatusException(HttpStatus.GONE, "Invite is no longer valid");
        }
        if (invite.locked()) throw new ResponseStatusException(HttpStatus.LOCKED, "Room is locked");
        if (invite.policy() == AccessPolicy.INVITE_AND_KEY
                && (accessKey == null || invite.keyVerifier() == null || !passwordEncoder.matches(accessKey, invite.keyVerifier()))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "A valid room key is also required");
        }
        Integer memberCount = jdbc.sql("SELECT count(*) FROM room_members WHERE room_id = :roomId AND status = 'ACTIVE'")
                .param("roomId", invite.roomId()).query(Integer.class).single();
        if (memberCount >= invite.maxMembers()) throw new ResponseStatusException(HttpStatus.CONFLICT, "Room is full");

        String status = invite.approvalRequired() ? "PENDING" : "ACTIVE";
        jdbc.sql("""
                        INSERT INTO room_members (room_id, user_id, role, status)
                        VALUES (:roomId, :userId, :role, :status)
                        ON CONFLICT (room_id, user_id) DO UPDATE SET role = EXCLUDED.role, status = EXCLUDED.status
                        """)
                .param("roomId", invite.roomId()).param("userId", user.id())
                .param("role", invite.role().name()).param("status", status).update();
        jdbc.sql("UPDATE room_invites SET used_count = used_count + 1 WHERE id = :id")
                .param("id", invite.id()).update();
        return new AccessResult(invite.roomId(), !invite.approvalRequired(), invite.role(), status);
    }

    public MediaToken createMediaToken(CurrentUser user, UUID roomId) {
        var membership = jdbc.sql("""
                        SELECT rm.role, rm.can_share_screen, r.screen_share_policy FROM room_members rm JOIN rooms r ON r.id=rm.room_id
                        WHERE rm.room_id = :roomId AND rm.user_id = :userId AND rm.status = 'ACTIVE'
                        """)
                .param("roomId", roomId)
                .param("userId", user.id())
                .query((rs,n)->new ShareAccess(RoomRole.valueOf(rs.getString("role")),rs.getBoolean("can_share_screen"),rs.getString("screen_share_policy")))
                  .optional();
        if (membership.isEmpty()) {
            log.warn("Media token denied: roomId={}, userId={}, username={}", roomId, user.id(), user.username());
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Active room membership required");
        }
        ShareAccess shareAccess = membership.get();
        log.info("Media token granted: roomId={}, userId={}, username={}, role={}",
                roomId, user.id(), user.username(), shareAccess.role());
        RoomRole role = shareAccess.role();
        // An explicit per-member grant from the room owner always permits that
        // member to publish, including while the room default is HOSTS_ONLY.
        boolean canPublish = role == RoomRole.HOST || role == RoomRole.CO_HOST
                || shareAccess.policy().equals("EVERYONE") || shareAccess.allowed();
        String mediaRoomName = "room-" + roomId;

        AccessToken token = new AccessToken(liveKitApiKey, liveKitApiSecret);
        token.setIdentity(user.id().toString());
        token.setName(user.displayName());
        token.setTtl(TimeUnit.HOURS.toMillis(1));
        List<String> publishSources = canPublish
                ? List.of("microphone", "screen_share", "screen_share_audio")
                : List.of("microphone");
        token.addGrants(
                new RoomJoin(true),
                new RoomName(mediaRoomName),
                new CanSubscribe(true),
                new CanPublish(true),
                new CanPublishSources(publishSources),
                new CanPublishData(true));
        return new MediaToken(liveKitUrl, token.toJwt(), mediaRoomName, canPublish);
    }

    private String generateSecret() {
        byte[] bytes = new byte[16];
        random.nextBytes(bytes);
        String value = HexFormat.of().withUpperCase().formatHex(bytes);
        return value.substring(0, 8) + "-" + value.substring(8, 16) + "-" + value.substring(16, 24) + "-" + value.substring(24);
    }

    private record RoomAccess(
            AccessPolicy policy,
            String keyVerifier,
            boolean locked,
            boolean approvalRequired,
            int maxMembers,
            String visibility,
            UUID ownerId) {
    }

    private record InviteAccess(UUID id, UUID roomId, RoomRole role, Instant expiresAt, Integer maxUses,
                                int usedCount, boolean revoked, AccessPolicy policy, String keyVerifier,
                                boolean locked, boolean approvalRequired, int maxMembers) {
    }
    private record ShareAccess(RoomRole role, boolean allowed, String policy) {}
}

