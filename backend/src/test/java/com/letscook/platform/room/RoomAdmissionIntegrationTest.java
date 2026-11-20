package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.mock;

/** Runs against PostgreSQL in a transaction-local schema, rolled back after each case. */
@EnabledIfEnvironmentVariable(named = "ROOM_TEST_DATABASE_URL", matches = ".+")
class RoomAdmissionIntegrationTest {
    private Connection connection;
    private JdbcClient jdbc;
    private RoomRepository rooms;
    private final CurrentUser owner = new CurrentUser(UUID.randomUUID(), "owner", "Owner", "");
    private final CurrentUser guest = new CurrentUser(UUID.randomUUID(), "guest", "Guest", "");
    private final UUID roomId = UUID.randomUUID();

    @BeforeEach
    void setUp() throws Exception {
        connection = DriverManager.getConnection(System.getenv("ROOM_TEST_DATABASE_URL"),
                System.getenv("ROOM_TEST_DATABASE_USER"), System.getenv("ROOM_TEST_DATABASE_PASSWORD"));
        connection.setAutoCommit(false);
        jdbc = JdbcClient.create(new SingleConnectionDataSource(connection, true));
        String schema = "admission_test_" + UUID.randomUUID().toString().replace("-", "");
        jdbc.sql("CREATE SCHEMA " + schema).update();
        jdbc.sql("SET LOCAL search_path TO " + schema).update();
        jdbc.sql("""
                CREATE TABLE rooms(id uuid PRIMARY KEY, owner_id uuid, access_policy text,
                  key_verifier text, locked boolean DEFAULT false, approval_required boolean DEFAULT false,
                  max_members integer DEFAULT 25, visibility text, name text DEFAULT 'Test room');
                CREATE TABLE room_members(room_id uuid, user_id uuid, role text,
                  status text DEFAULT 'ACTIVE', can_view_video boolean DEFAULT false,
                  video_access_requested boolean DEFAULT false, can_add_videos boolean DEFAULT false,
                  can_share_screen boolean DEFAULT false, invited_by uuid, PRIMARY KEY(room_id,user_id));
                CREATE TABLE friendships(requester_id uuid,addressee_id uuid,status text);
                CREATE TABLE user_blocks(blocker_id uuid,blocked_id uuid);
                CREATE TABLE app_users(id uuid, restrict_invites boolean DEFAULT false,
                  identity_subject text DEFAULT '');
                CREATE TABLE room_invites(id uuid,room_id uuid,role_granted text,expires_at timestamptz,
                  max_uses integer,used_count integer DEFAULT 0,revoked boolean DEFAULT false,code text)
                """).update();
        jdbc.sql("INSERT INTO rooms(id,owner_id,access_policy,visibility) VALUES(:r,:u,'OPEN','PUBLIC')")
                .param("r", roomId).param("u", owner.id()).update();
        jdbc.sql("INSERT INTO room_members(room_id,user_id,role) VALUES(:r,:u,'HOST')")
                .param("r", roomId).param("u", owner.id()).update();
        ScriptUtils.executeSqlScript(connection,
                new ClassPathResource("db/migration/V29__admitted_members_can_view_video.sql"));
        rooms = new RoomRepository(jdbc, mock(PasswordEncoder.class), mock(LiveKitSettings.class),
                mock(SimpMessagingTemplate.class));
    }

    @AfterEach
    void tearDown() throws Exception {
        if (connection != null) {
            connection.rollback();
            connection.close();
        }
    }

    @Test
    void publicAdmissionGrantsViewingWithoutPlaybackOrScreenControls() {
        assertThat(rooms.unlock(guest, roomId, null).accessGranted()).isTrue();
        assertViewerOnly();
        new WatchRepository(jdbc).setVideoAccess(roomId, guest.id(), false);
        rooms.unlock(guest, roomId, null);
        assertThat(canView()).isFalse();
    }

    @Test
    void friendsRoomAdmitsAnAcceptedFriendAndRejectsAStranger() {
        jdbc.sql("UPDATE rooms SET visibility='FRIENDS'").update();
        assertThatThrownBy(() -> rooms.unlock(guest, roomId, null))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(error -> ((ResponseStatusException) error).getStatusCode().value()).isEqualTo(403);
        jdbc.sql("INSERT INTO friendships VALUES(:a,:b,'ACCEPTED')")
                .param("a", guest.id()).param("b", owner.id()).update();
        assertThat(rooms.unlock(guest, roomId, null).accessGranted()).isTrue();
        assertViewerOnly();
    }

    @Test
    void inviteOnlyAdmissionGrantsViewingAfterAValidInvite() {
        jdbc.sql("UPDATE rooms SET visibility='PRIVATE',access_policy='INVITE_ONLY'").update();
        assertThatThrownBy(() -> rooms.unlock(guest, roomId, null)).isInstanceOf(ResponseStatusException.class);
        jdbc.sql("INSERT INTO room_invites(id,room_id,role_granted,code) VALUES(:i,:r,'MEMBER','test-code')")
                .param("i", UUID.randomUUID()).param("r", roomId).update();
        assertThat(rooms.acceptInvite(guest, "test-code", null).accessGranted()).isTrue();
        assertViewerOnly();
    }

    @Test
    void targetedInviteGrantsViewingAndHonorsFriendOnlyInvitations() {
        jdbc.sql("INSERT INTO app_users(id,restrict_invites) VALUES(:u,true)")
                .param("u", guest.id()).update();
        assertThatThrownBy(() -> rooms.inviteUser(owner, roomId, guest.id()))
                .isInstanceOf(ResponseStatusException.class);
        jdbc.sql("INSERT INTO friendships VALUES(:a,:b,'ACCEPTED')")
                .param("a", guest.id()).param("b", owner.id()).update();
        rooms.inviteUser(owner, roomId, guest.id());
        assertViewerOnly();
    }

    @Test
    void approvalGrantsViewingToALegacyPendingMember() {
        jdbc.sql("UPDATE rooms SET approval_required=true").update();
        assertThat(rooms.unlock(guest, roomId, null).accessGranted()).isFalse();
        jdbc.sql("UPDATE room_members SET can_view_video=false,video_access_requested=true WHERE user_id=:u")
                .param("u", guest.id()).update();
        rooms.decideJoinRequest(owner, roomId, guest.id(), true);
        assertViewerOnly();
        assertThat(jdbc.sql("SELECT status FROM room_members WHERE user_id=:u")
                .param("u", guest.id()).query(String.class).single()).isEqualTo("ACTIVE");
    }

    @Test
    void migrationRepairsPreviouslyAdmittedMembers() {
        rooms.unlock(guest, roomId, null);
        jdbc.sql("UPDATE room_members SET can_view_video=false,video_access_requested=true WHERE user_id=:u")
                .param("u", guest.id()).update();
        ScriptUtils.executeSqlScript(connection,
                new ClassPathResource("db/migration/V29__admitted_members_can_view_video.sql"));
        assertViewerOnly();
        assertThat(jdbc.sql("SELECT video_access_requested FROM room_members WHERE user_id=:u")
                .param("u", guest.id()).query(Boolean.class).single()).isFalse();
    }

    private boolean canView() {
        return jdbc.sql("SELECT can_view_video FROM room_members WHERE user_id=:u")
                .param("u", guest.id()).query(Boolean.class).single();
    }

    private void assertViewerOnly() {
        assertThat(canView()).isTrue();
        assertThat(jdbc.sql("SELECT can_add_videos OR can_share_screen FROM room_members WHERE user_id=:u")
                .param("u", guest.id()).query(Boolean.class).single()).isFalse();
        assertThat(jdbc.sql("SELECT role FROM room_members WHERE user_id=:u")
                .param("u", guest.id()).query(String.class).single()).isEqualTo("MEMBER");
    }
}
