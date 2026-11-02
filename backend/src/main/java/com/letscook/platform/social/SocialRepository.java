package com.letscook.platform.social;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Social persistence for friendships, pending requests, blocks, direct messages, unread summaries,
 * shared-watch duration, and target identity lookup for real-time delivery.
 */
@Repository
class SocialRepository {
    private final JdbcClient jdbc; SocialRepository(JdbcClient jdbc){this.jdbc=jdbc;}
    List<SocialModels.Friend> friends(UUID me){return jdbc.sql("""
        SELECT u.id,u.username,u.display_name,u.avatar_url,(u.last_seen_at > now()-interval '75 seconds') online,
        COALESCE((SELECT SUM(GREATEST(0,EXTRACT(EPOCH FROM LEAST(COALESCE(mine.left_at,now()),COALESCE(theirs.left_at,now()))-GREATEST(mine.joined_at,theirs.joined_at))))::bigint FROM user_room_sessions mine JOIN user_room_sessions theirs ON theirs.room_id=mine.room_id AND theirs.user_id=u.id AND mine.joined_at<COALESCE(theirs.left_at,now()) AND theirs.joined_at<COALESCE(mine.left_at,now()) WHERE mine.user_id=:me),0) watch_together_seconds
        FROM friendships f JOIN app_users u ON u.id=CASE WHEN f.requester_id=:me THEN f.addressee_id ELSE f.requester_id END
        WHERE (f.requester_id=:me OR f.addressee_id=:me) AND f.status='ACCEPTED' AND NOT EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=:me AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=:me)) ORDER BY online DESC,u.display_name
        """).param("me",me).query((rs,n)->new SocialModels.Friend(rs.getObject("id",UUID.class),rs.getString("username"),rs.getString("display_name"),rs.getString("avatar_url"),rs.getBoolean("online"),rs.getLong("watch_together_seconds"))).list();}
    List<SocialModels.FriendRequest> requests(UUID me){return jdbc.sql("SELECT f.id,u.id user_id,u.username,u.display_name FROM friendships f JOIN app_users u ON u.id=f.requester_id WHERE f.addressee_id=:me AND f.status='PENDING' ORDER BY f.created_at").param("me",me).query((rs,n)->new SocialModels.FriendRequest(rs.getObject("id",UUID.class),rs.getObject("user_id",UUID.class),rs.getString("username"),rs.getString("display_name"))).list();}
    List<SocialModels.Notification> requestNotifications(UUID me){return jdbc.sql("SELECT f.id,u.id user_id,u.username,u.display_name,f.created_at FROM friendships f JOIN app_users u ON u.id=f.requester_id WHERE f.addressee_id=:me AND f.status='PENDING'").param("me",me).query((rs,n)->new SocialModels.Notification(rs.getObject("id",UUID.class),"FRIEND_REQUEST",rs.getObject("user_id",UUID.class),rs.getString("username"),rs.getString("display_name"),null,1,rs.getTimestamp("created_at").toInstant())).list();}
    List<SocialModels.Notification> messageNotifications(UUID me){return jdbc.sql("""
        SELECT DISTINCT ON (m.sender_id) m.id,m.sender_id user_id,u.username,u.display_name,COALESCE(NULLIF(m.body,''),CASE m.attachment_type WHEN 'IMAGE' THEN 'Sent a photo' WHEN 'VIDEO' THEN 'Sent a video' END) body,m.created_at,COUNT(*) OVER(PARTITION BY m.sender_id) unread_count
        FROM direct_messages m JOIN app_users u ON u.id=m.sender_id WHERE m.recipient_id=:me AND m.read_at IS NULL ORDER BY m.sender_id,m.created_at DESC
        """).param("me",me).query((rs,n)->new SocialModels.Notification(rs.getObject("id",UUID.class),"DIRECT_MESSAGE",rs.getObject("user_id",UUID.class),rs.getString("username"),rs.getString("display_name"),rs.getString("body"),rs.getInt("unread_count"),rs.getTimestamp("created_at").toInstant())).list();}
    boolean blockedBetween(UUID a,UUID b){return jdbc.sql("SELECT EXISTS(SELECT 1 FROM user_blocks WHERE (blocker_id=:a AND blocked_id=:b) OR (blocker_id=:b AND blocked_id=:a))").param("a",a).param("b",b).query(Boolean.class).single();}
    void createRequest(UUID id,UUID me,UUID them){jdbc.sql("INSERT INTO friendships(id,requester_id,addressee_id) VALUES(:id,:me,:them)").param("id",id).param("me",me).param("them",them).update();}
    int accept(UUID id,UUID me){return jdbc.sql("UPDATE friendships SET status='ACCEPTED',updated_at=now() WHERE id=:id AND addressee_id=:me AND status='PENDING'").param("id",id).param("me",me).update();}
    int reject(UUID id,UUID me){return jdbc.sql("DELETE FROM friendships WHERE id=:id AND addressee_id=:me AND status='PENDING'").param("id",id).param("me",me).update();}
    List<SocialModels.BlockedPerson> blocked(UUID me){return jdbc.sql("SELECT u.id,u.username,u.display_name,u.avatar_url,b.created_at FROM user_blocks b JOIN app_users u ON u.id=b.blocked_id WHERE b.blocker_id=:me ORDER BY b.created_at DESC LIMIT 500").param("me",me).query((rs,n)->new SocialModels.BlockedPerson(rs.getObject("id",UUID.class),rs.getString("username"),rs.getString("display_name"),rs.getString("avatar_url"),rs.getTimestamp("created_at").toInstant())).list();}
    void addBlock(UUID me,UUID them){jdbc.sql("INSERT INTO user_blocks(blocker_id,blocked_id) VALUES(:me,:them) ON CONFLICT DO NOTHING").param("me",me).param("them",them).update();}
    void removeFriendship(UUID me,UUID them){jdbc.sql("DELETE FROM friendships WHERE (requester_id=:me AND addressee_id=:them) OR (requester_id=:them AND addressee_id=:me)").param("me",me).param("them",them).update();}
    void markMessagesRead(UUID sender,UUID recipient){jdbc.sql("UPDATE direct_messages SET read_at=COALESCE(read_at,now()) WHERE sender_id=:sender AND recipient_id=:recipient").param("sender",sender).param("recipient",recipient).update();}
    void removeBlock(UUID me,UUID them){jdbc.sql("DELETE FROM user_blocks WHERE blocker_id=:me AND blocked_id=:them").param("me",me).param("them",them).update();}
    boolean areFriends(UUID a,UUID b){return jdbc.sql("SELECT EXISTS(SELECT 1 FROM friendships WHERE status='ACCEPTED' AND ((requester_id=:a AND addressee_id=:b) OR (requester_id=:b AND addressee_id=:a))) AND NOT EXISTS(SELECT 1 FROM user_blocks WHERE (blocker_id=:a AND blocked_id=:b) OR (blocker_id=:b AND blocked_id=:a))").param("a",a).param("b",b).query(Boolean.class).single();}
    List<SocialModels.Message> messages(UUID me,UUID friend){return jdbc.sql("SELECT id,sender_id,recipient_id,body,attachment_type,attachment_url,attachment_name,created_at FROM direct_messages WHERE (sender_id=:me AND recipient_id=:friend) OR (sender_id=:friend AND recipient_id=:me) ORDER BY created_at DESC LIMIT 100").param("me",me).param("friend",friend).query((rs,n)->new SocialModels.Message(rs.getObject("id",UUID.class),rs.getObject("sender_id",UUID.class),rs.getObject("recipient_id",UUID.class),rs.getString("body"),rs.getString("attachment_type"),rs.getString("attachment_url"),rs.getString("attachment_name"),rs.getTimestamp("created_at").toInstant())).list();}
    void insertMessage(SocialModels.Message m){jdbc.sql("INSERT INTO direct_messages(id,sender_id,recipient_id,body,attachment_type,attachment_url,attachment_name,created_at) VALUES(:id,:sender,:recipient,:body,:type,:url,:name,:created)").param("id",m.id()).param("sender",m.senderId()).param("recipient",m.recipientId()).param("body",m.body()).param("type",m.attachmentType()).param("url",m.attachmentUrl()).param("name",m.attachmentName()).param("created",Timestamp.from(m.createdAt())).update();}
    Optional<String> subject(UUID id){return jdbc.sql("SELECT identity_subject FROM app_users WHERE id=:id").param("id",id).query(String.class).optional();}
}
