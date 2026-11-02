package com.letscook.platform.common;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Profile persistence: user fields, privacy settings, preferences, interests, connections,
 * gallery projections, social counts, and avatar references.
 */
@Repository
class ProfileRepository {
    private final JdbcClient jdbc;
    ProfileRepository(JdbcClient jdbc){this.jdbc=jdbc;}

    ProfileModels.ProfileView profile(UUID id){
        return jdbc.sql("SELECT id,username,display_name,email,bio,avatar_url FROM app_users WHERE id=:id").param("id",id)
                .query((rs,n)->new ProfileModels.ProfileView(rs.getObject("id",UUID.class),rs.getString("username"),rs.getString("display_name"),rs.getString("email"),rs.getString("bio"),rs.getString("avatar_url"))).single();
    }
    void update(UUID id,ProfileModels.UpdateProfile input){jdbc.sql("UPDATE app_users SET display_name=COALESCE(:name,display_name), bio=COALESCE(:bio,bio), updated_at=now() WHERE id=:id").param("name",input.displayName()).param("bio",input.bio()).param("id",id).update();}
    List<ProfileModels.Connection> connections(UUID id){return jdbc.sql("SELECT provider,url FROM user_profile_connections WHERE user_id=:id ORDER BY provider").param("id",id).query((rs,n)->new ProfileModels.Connection(rs.getString(1),rs.getString(2))).list();}
    List<String> interests(UUID id){return jdbc.sql("SELECT interest FROM user_profile_interests WHERE user_id=:id ORDER BY interest").param("id",id).query(String.class).list();}
    boolean areFriends(UUID a,UUID b){return jdbc.sql("SELECT EXISTS(SELECT 1 FROM friendships WHERE status='ACCEPTED' AND ((requester_id=:a AND addressee_id=:b) OR (requester_id=:b AND addressee_id=:a)))").param("a",a).param("b",b).query(Boolean.class).single();}
    List<Map<String,Object>> gallery(UUID id,boolean hideSensitive){return media(id,"in_gallery=true",hideSensitive);}
    List<Map<String,Object>> history(UUID id,boolean hideSensitive){return media(id,"history_visible=true",hideSensitive);}
    List<Map<String,Object>> likes(UUID id,boolean hideSensitive){return media(id,"liked=true",hideSensitive);}
    private List<Map<String,Object>> media(UUID id,String filter,boolean hideSensitive){return jdbc.sql("SELECT media_id,provider,title,thumbnail_url,play_count,watch_seconds,last_watched_at FROM user_media_history WHERE user_id=:id AND "+filter+(hideSensitive?" AND sensitive=false":"")+" ORDER BY last_watched_at DESC LIMIT 60").param("id",id).query((rs,n)->{Map<String,Object> item=new LinkedHashMap<>();item.put("mediaId",rs.getString(1));item.put("provider",rs.getString(2));item.put("title",rs.getString(3));item.put("thumbnailUrl",rs.getString(4));item.put("playCount",rs.getInt(5));item.put("watchSeconds",rs.getLong(6));item.put("lastWatchedAt",rs.getTimestamp(7).toInstant());return item;}).list();}
    long watchSeconds(UUID id){return jdbc.sql("SELECT COALESCE(SUM(duration_seconds),0) FROM user_room_sessions WHERE user_id=:id").param("id",id).query(Long.class).single();}
    int friendCount(UUID id){return jdbc.sql("SELECT COUNT(*) FROM friendships WHERE status='ACCEPTED' AND (requester_id=:id OR addressee_id=:id)").param("id",id).query(Integer.class).single();}
    Instant createdAt(UUID id){return jdbc.sql("SELECT created_at FROM app_users WHERE id=:id").param("id",id).query(Instant.class).single();}
    Instant lastSeenAt(UUID id){return jdbc.sql("SELECT last_seen_at FROM app_users WHERE id=:id").param("id",id).query(Instant.class).single();}
    boolean online(UUID id){return jdbc.sql("SELECT last_seen_at > now()-interval '75 seconds' FROM app_users WHERE id=:id").param("id",id).query(Boolean.class).single();}
    boolean hideSensitiveContent(UUID id){return jdbc.sql("SELECT hide_sensitive_content FROM app_users WHERE id=:id").param("id",id).query(Boolean.class).single();}
    Map<String,Object> relationship(UUID viewer,UUID target){return jdbc.sql("""
        SELECT id,status,requester_id=:viewer outgoing FROM friendships
        WHERE (requester_id=:viewer AND addressee_id=:target) OR (requester_id=:target AND addressee_id=:viewer)
        LIMIT 1
        """).param("viewer",viewer).param("target",target).query((rs,n)->{Map<String,Object> value=new LinkedHashMap<>();value.put("id",rs.getObject("id",UUID.class));value.put("status",rs.getString("status"));value.put("outgoing",rs.getBoolean("outgoing"));return value;}).optional().orElseGet(()->{Map<String,Object> value=new LinkedHashMap<>();value.put("status","NONE");value.put("outgoing",false);return value;});}
    List<Map<String,Object>> dailyActivity(UUID id){return jdbc.sql("""
        WITH days AS (SELECT generate_series((SELECT created_at::date FROM app_users WHERE id=:id),current_date,interval '1 day')::date AS activity_day), totals AS (
          SELECT joined_at::date AS activity_day,SUM(duration_seconds + CASE WHEN left_at IS NULL THEN COALESCE((
            SELECT GREATEST(0,EXTRACT(EPOCH FROM LEAST(now(),p.last_seen_at+interval '45 seconds')-user_room_sessions.joined_at)::bigint)
            FROM room_live_presence p WHERE p.user_id=user_room_sessions.user_id AND p.room_id=user_room_sessions.room_id
          ),0) ELSE 0 END) seconds
          FROM user_room_sessions WHERE user_id=:id GROUP BY joined_at::date)
        SELECT d.activity_day,COALESCE(t.seconds,0) seconds FROM days d LEFT JOIN totals t USING(activity_day) ORDER BY d.activity_day
        """).param("id",id).query((rs,n)->{Map<String,Object> value=new LinkedHashMap<>();value.put("day",rs.getDate("activity_day").toLocalDate());value.put("seconds",rs.getLong("seconds"));return value;}).list();}
    List<Map<String,Object>> watchFriends(UUID id){return jdbc.sql("""
        SELECT u.id,u.username,u.display_name,u.avatar_url,
          COALESCE((SELECT SUM(GREATEST(0,EXTRACT(EPOCH FROM LEAST(COALESCE(mine.left_at,now()),COALESCE(theirs.left_at,now()))-GREATEST(mine.joined_at,theirs.joined_at))))::bigint
            FROM user_room_sessions mine JOIN user_room_sessions theirs ON theirs.room_id=mine.room_id AND theirs.user_id=u.id
            AND mine.joined_at<COALESCE(theirs.left_at,now()) AND theirs.joined_at<COALESCE(mine.left_at,now()) WHERE mine.user_id=:id),0) watch_seconds
        FROM friendships f JOIN app_users u ON u.id=CASE WHEN f.requester_id=:id THEN f.addressee_id ELSE f.requester_id END
        WHERE (f.requester_id=:id OR f.addressee_id=:id) AND f.status='ACCEPTED'
        ORDER BY watch_seconds DESC,u.display_name LIMIT 24
        """).param("id",id).query((rs,n)->{UUID friendId=rs.getObject("id",UUID.class);Map<String,Object> value=new LinkedHashMap<>();value.put("id",friendId);value.put("username",PublicIdentity.handle(rs.getString("username"),friendId));value.put("displayName",rs.getString("display_name"));value.put("avatarUrl",rs.getString("avatar_url"));value.put("watchSeconds",rs.getLong("watch_seconds"));return value;}).list();}
    Map<String,Long> providerUsage(UUID id,boolean hideSensitive){return jdbc.sql("SELECT provider,SUM(GREATEST(watch_seconds,play_count*60)) weight FROM user_media_history WHERE user_id=:id AND history_visible=true"+(hideSensitive?" AND sensitive=false":"")+" GROUP BY provider ORDER BY weight DESC").param("id",id).query((rs,n)->Map.entry(rs.getString("provider"),rs.getLong("weight"))).list().stream().collect(java.util.stream.Collectors.toMap(Map.Entry::getKey,Map.Entry::getValue,(a,b)->a,LinkedHashMap::new));}
    Map<String,Long> inferredInterests(UUID id,boolean hideSensitive){return jdbc.sql("""
        SELECT CASE
          WHEN provider='CRUNCHYROLL' OR lower(title) ~ '(anime|manga)' THEN 'Anime'
          WHEN lower(title) ~ '(music|song|concert|lyrics)' THEN 'Music'
          WHEN lower(title) ~ '(game|gaming|minecraft|pubg)' THEN 'Gaming'
          WHEN lower(title) ~ '(cook|recipe|food|kitchen)' THEN 'Food'
          WHEN lower(title) ~ '(cricket|football|sport|match)' THEN 'Sports'
          WHEN lower(title) ~ '(news|politic|election)' THEN 'News'
          WHEN lower(title) ~ '(learn|tutorial|course|how to)' THEN 'Learning'
          ELSE 'Entertainment' END interest,SUM(GREATEST(watch_seconds,play_count*60)) weight
        FROM user_media_history WHERE user_id=:id AND history_visible=true
        """+(hideSensitive?" AND sensitive=false":"")+" GROUP BY interest ORDER BY weight DESC LIMIT 8").param("id",id).query((rs,n)->Map.entry(rs.getString("interest"),rs.getLong("weight"))).list().stream().collect(java.util.stream.Collectors.toMap(Map.Entry::getKey,Map.Entry::getValue,(a,b)->a,LinkedHashMap::new));}
    ProfileModels.ProfileVisibility visibility(UUID id){return jdbc.sql("SELECT bio_visibility,gallery_visibility,activity_visibility,stats_visibility,friends_visibility,interests_visibility,connections_visibility FROM app_users WHERE id=:id").param("id",id).query((rs,n)->new ProfileModels.ProfileVisibility(rs.getString(1),rs.getString(2),rs.getString(3),rs.getString(4),rs.getString(5),rs.getString(6),rs.getString(7))).single();}
    void updateVisibility(UUID id,ProfileModels.ProfileVisibility v){jdbc.sql("""
        UPDATE app_users SET bio_visibility=:bio,gallery_visibility=:gallery,activity_visibility=:activity,
        stats_visibility=:stats,friends_visibility=:friends,interests_visibility=:interests,
        connections_visibility=:connections,updated_at=now() WHERE id=:id
        """).param("bio",v.bio()).param("gallery",v.gallery()).param("activity",v.activity()).param("stats",v.stats()).param("friends",v.friends()).param("interests",v.interests()).param("connections",v.connections()).param("id",id).update();}
    ProfileModels.Preferences preferences(UUID id){return jdbc.sql("""
        SELECT hide_sensitive_content,hide_location,restrict_invites,floating_video,mute_other_audio,
        haptic_feedback,auto_translate,preferred_language,quick_reaction FROM app_users WHERE id=:id
        """).param("id",id).query((rs,n)->new ProfileModels.Preferences(rs.getBoolean(1),rs.getBoolean(2),rs.getBoolean(3),rs.getBoolean(4),rs.getBoolean(5),rs.getBoolean(6),rs.getBoolean(7),rs.getString(8),rs.getString(9))).single();}
    void updatePreferences(UUID id,ProfileModels.PreferencesPatch input,String language,String reaction){jdbc.sql("""
        UPDATE app_users SET hide_sensitive_content=COALESCE(:mature,hide_sensitive_content),hide_location=COALESCE(:location,hide_location),
        restrict_invites=COALESCE(:invites,restrict_invites),floating_video=COALESCE(:floating,floating_video),
        mute_other_audio=COALESCE(:mute,mute_other_audio),haptic_feedback=COALESCE(:haptic,haptic_feedback),
        auto_translate=COALESCE(:translate,auto_translate),preferred_language=COALESCE(:language,preferred_language),
        quick_reaction=COALESCE(:reaction,quick_reaction),updated_at=now() WHERE id=:id
        """).param("mature",input.hideSensitiveContent()).param("location",input.hideLocation()).param("invites",input.restrictInvites()).param("floating",input.floatingVideo()).param("mute",input.muteOtherAudio()).param("haptic",input.hapticFeedback()).param("translate",input.autoTranslate()).param("language",language).param("reaction",reaction).param("id",id).update();}
    void deleteConnections(UUID id){jdbc.sql("DELETE FROM user_profile_connections WHERE user_id=:id").param("id",id).update();}
    void addConnection(UUID id,ProfileModels.Connection value){jdbc.sql("INSERT INTO user_profile_connections(user_id,provider,url) VALUES(:id,:provider,:url)").param("id",id).param("provider",value.provider()).param("url",value.url()).update();}
    void deleteInterests(UUID id){jdbc.sql("DELETE FROM user_profile_interests WHERE user_id=:id").param("id",id).update();}
    void addInterest(UUID id,String value){jdbc.sql("INSERT INTO user_profile_interests(user_id,interest) VALUES(:id,:interest)").param("id",id).param("interest",value).update();}
    String avatarUrl(UUID id){return jdbc.sql("SELECT avatar_url FROM app_users WHERE id=:id").param("id",id).query(String.class).optional().orElse(null);}
    void updateAvatar(UUID id,String url){jdbc.sql("UPDATE app_users SET avatar_url=:avatar,updated_at=now() WHERE id=:id").param("avatar",url).param("id",id).update();}
}
