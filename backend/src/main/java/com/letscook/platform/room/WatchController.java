package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.util.UriComponentsBuilder;
import tools.jackson.databind.JsonNode;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;

@RestController @RequestMapping("/api")
public class WatchController {
 private final JdbcClient jdbc; private final CurrentUserService users; private final String key; private final RestClient rest=RestClient.create();
 public WatchController(JdbcClient jdbc,CurrentUserService users,@Value("${app.youtube.api-key:}") String key){this.jdbc=jdbc;this.users=users;this.key=key;}

 @GetMapping("/rooms/{roomId}/watch") WatchState state(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId){
  CurrentUser u=users.synchronize(jwt);member(roomId,u.id());
  return jdbc.sql("SELECT provider,media_id,title,playing,position_seconds,playback_rate,updated_at,transition_until FROM room_watch_state WHERE room_id=:r").param("r",roomId).query((rs,n)->{
   boolean p=rs.getBoolean("playing");double rate=rs.getDouble("playback_rate"),pos=rs.getDouble("position_seconds");Instant at=rs.getTimestamp("updated_at").toInstant();Instant transition=rs.getTimestamp("transition_until")==null?null:rs.getTimestamp("transition_until").toInstant();Instant start=transition!=null&&transition.isAfter(at)?transition:at;
   if(p&&Instant.now().isAfter(start))pos+=Math.max(0,(Instant.now().toEpochMilli()-start.toEpochMilli())/1000d)*rate;
   return new WatchState(rs.getString("provider"),rs.getString("media_id"),rs.getString("title"),p,pos,rate,at,transition);
  }).optional().orElse(null);
 }

 @PutMapping("/rooms/{roomId}/watch") @Transactional WatchState update(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@Valid @RequestBody WatchUpdate x){
  CurrentUser u=users.synchronize(jwt);host(roomId,u.id());if(!x.provider().equals("YOUTUBE"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Provider is not playable yet");
  saveState(roomId,u.id(),x.provider(),x.mediaId(),x.title(),x.playing(),x.positionSeconds(),x.playbackRate(),null);return state(jwt,roomId);
 }

 @PostMapping("/rooms/{roomId}/watch/heartbeat") @Transactional WatchState heartbeat(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId){
  CurrentUser u=users.synchronize(jwt);host(roomId,u.id());
  jdbc.sql("""
    UPDATE room_watch_state SET position_seconds=position_seconds+
      CASE WHEN playing AND (transition_until IS NULL OR transition_until<=now()) THEN EXTRACT(EPOCH FROM (now()-GREATEST(updated_at,COALESCE(transition_until,updated_at))))*playback_rate ELSE 0 END,
      updated_at=now() WHERE room_id=:r
    """).param("r",roomId).update();return state(jwt,roomId);
 }

 @GetMapping("/rooms/{roomId}/watch/queue") QueueResponse queue(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId){
  CurrentUser u=users.synchronize(jwt);member(roomId,u.id());QueueSettings s=jdbc.sql("SELECT watch_queue_mode,watch_transition_seconds FROM rooms WHERE id=:r").param("r",roomId).query((rs,n)->new QueueSettings(rs.getString(1),rs.getInt(2))).single();
  List<QueueItem> items=jdbc.sql("""
    SELECT q.id,q.provider,q.media_id,q.title,q.thumbnail_url,q.added_by,u.display_name,q.personal_position,q.created_at,COUNT(v.user_id) vote_count,BOOL_OR(v.user_id=:u) voted
    FROM room_watch_queue q JOIN app_users u ON u.id=q.added_by LEFT JOIN room_watch_votes v ON v.queue_id=q.id
    WHERE q.room_id=:r AND q.status='QUEUED' GROUP BY q.id,u.display_name
    ORDER BY q.added_by,q.personal_position,q.created_at,q.id
    """).param("r",roomId).param("u",u.id()).query((rs,n)->new QueueItem(rs.getObject("id",UUID.class),rs.getString("provider"),rs.getString("media_id"),rs.getString("title"),rs.getString("thumbnail_url"),rs.getObject("added_by",UUID.class),rs.getString("display_name"),rs.getInt("personal_position"),rs.getInt("vote_count"),rs.getBoolean("voted"),rs.getTimestamp("created_at").toInstant())).list();
  List<QueueItem> roomItems=roomCandidates(items);SkipStatus skip=skipStatus(roomId,u.id());
  return new QueueResponse(s.mode(),s.transitionSeconds(),canAdd(roomId,u.id()),pickNext(roomItems,u.id()).map(QueueItem::id).orElse(null),skip.votes(),skip.required(),skip.votedByMe(),items);
 }

 @PostMapping("/rooms/{roomId}/watch/queue") @Transactional QueueItem addQueue(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@Valid @RequestBody QueueAdd x){
  CurrentUser u=users.synchronize(jwt);member(roomId,u.id());if(!canAdd(roomId,u.id()))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"The host has not allowed you to add videos");String provider=x.provider().toUpperCase(Locale.ROOT);if(!List.of("YOUTUBE","NETFLIX","CRUNCHYROLL","TWITCH").contains(provider))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Unsupported provider");
  UUID existing=jdbc.sql("SELECT id FROM room_watch_queue WHERE room_id=:r AND provider=:p AND media_id=:m AND status='QUEUED' ORDER BY created_at LIMIT 1").param("r",roomId).param("p",provider).param("m",x.mediaId()).query(UUID.class).optional().orElse(null);
  if(existing!=null){selectRoomVote(roomId,u.id(),existing);return queue(jwt,roomId).items().stream().filter(i->i.id().equals(existing)).findFirst().orElseThrow();}
  UUID id=UUID.randomUUID();
  Integer position=jdbc.sql("SELECT COALESCE(MAX(personal_position),-1)+1 FROM room_watch_queue WHERE room_id=:r AND added_by=:u AND status='QUEUED'").param("r",roomId).param("u",u.id()).query(Integer.class).single();
  jdbc.sql("INSERT INTO room_watch_queue(id,room_id,provider,media_id,title,thumbnail_url,added_by,personal_position) VALUES(:id,:r,:p,:m,:t,:thumb,:u,:position)").param("id",id).param("r",roomId).param("p",provider).param("m",x.mediaId()).param("t",x.title()).param("thumb",x.thumbnailUrl()).param("u",u.id()).param("position",position).update();
  if(position==0)selectRoomVote(roomId,u.id(),id);
  return queue(jwt,roomId).items().stream().filter(i->i.id().equals(id)).findFirst().orElseThrow();
 }

 @PutMapping("/rooms/{roomId}/watch/queue/reorder") @Transactional void reorder(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@RequestBody ReorderRequest request){
  CurrentUser u=users.synchronize(jwt);member(roomId,u.id());List<UUID> ids=request.queueIds()==null?List.of():request.queueIds();
  Set<UUID> owned=new HashSet<>(jdbc.sql("SELECT id FROM room_watch_queue WHERE room_id=:r AND added_by=:u AND status='QUEUED'").param("r",roomId).param("u",u.id()).query(UUID.class).list());
  if(ids.size()!=owned.size()||!owned.equals(new HashSet<>(ids)))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Reorder must contain your complete queue");
  for(int i=0;i<ids.size();i++)jdbc.sql("UPDATE room_watch_queue SET personal_position=:p WHERE id=:id AND room_id=:r AND added_by=:u").param("p",i).param("id",ids.get(i)).param("r",roomId).param("u",u.id()).update();
 }

 @PostMapping("/rooms/{roomId}/watch/skip-vote") @Transactional SkipVoteResult skipVote(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId){
  CurrentUser u=users.synchronize(jwt);String memberRole=role(roomId,u.id());boolean hostSkip=memberRole.equals("HOST");String media=jdbc.sql("SELECT media_id FROM room_watch_state WHERE room_id=:r").param("r",roomId).query(String.class).optional().orElseThrow(()->new ResponseStatusException(HttpStatus.CONFLICT,"Nothing is playing"));
  jdbc.sql("INSERT INTO room_watch_skip_votes(room_id,media_id,user_id) VALUES(:r,:m,:u) ON CONFLICT DO NOTHING").param("r",roomId).param("m",media).param("u",u.id()).update();SkipStatus status=skipStatus(roomId,u.id());
  if(hostSkip||status.votes()>=status.required()){
   QueueSettings settings=jdbc.sql("SELECT watch_queue_mode,watch_transition_seconds FROM rooms WHERE id=:r").param("r",roomId).query((rs,n)->new QueueSettings(rs.getString(1),rs.getInt(2))).single();
   List<NextVideo> candidates=nextCandidates(roomId);NextVideo next=pickNextVideo(candidates,u.id()).orElse(null);
   if(next==null){jdbc.sql("UPDATE room_watch_state SET playing=false,updated_at=now(),updated_by=:u,transition_until=NULL WHERE room_id=:r").param("u",u.id()).param("r",roomId).update();return new SkipVoteResult(true,status.votes(),status.required(),state(jwt,roomId));}
   if(!next.provider().equals("YOUTUBE"))throw new ResponseStatusException(HttpStatus.CONFLICT,next.provider()+" playback is not integrated yet");
   jdbc.sql("UPDATE room_watch_queue SET status='PLAYED' WHERE id=:id").param("id",next.id()).update();Instant starts=Instant.now().plus(Math.max(8,Math.min(10,settings.transitionSeconds())),ChronoUnit.SECONDS);saveState(roomId,u.id(),next.provider(),next.mediaId(),next.title(),true,0,1,starts);return new SkipVoteResult(true,status.votes(),status.required(),state(jwt,roomId));
  }
  return new SkipVoteResult(false,status.votes(),status.required(),null);
 }

 @PostMapping("/rooms/{roomId}/watch/queue/{queueId}/vote") @Transactional void vote(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID queueId){
  CurrentUser u=users.synchronize(jwt);member(roomId,u.id());boolean valid=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_watch_queue WHERE id=:q AND room_id=:r AND status='QUEUED')").param("q",queueId).param("r",roomId).query(Boolean.class).single();if(!valid)throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Queue item not found");boolean exists=jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_watch_votes WHERE queue_id=:q AND user_id=:u)").param("q",queueId).param("u",u.id()).query(Boolean.class).single();
  if(exists)jdbc.sql("DELETE FROM room_watch_votes WHERE queue_id=:q AND user_id=:u").param("q",queueId).param("u",u.id()).update();else selectRoomVote(roomId,u.id(),queueId);
 }

 @DeleteMapping("/rooms/{roomId}/watch/queue/{queueId}") void removeQueue(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID queueId){CurrentUser u=users.synchronize(jwt);manager(roomId,u.id());jdbc.sql("DELETE FROM room_watch_queue WHERE id=:q AND room_id=:r").param("q",queueId).param("r",roomId).update();}

 @PostMapping("/rooms/{roomId}/watch/queue/next") @Transactional WatchState playNext(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@RequestBody(required=false) NextRequest request){
  CurrentUser u=users.synchronize(jwt);host(roomId,u.id());UUID requested=request==null?null:request.queueId();QueueSettings settings=jdbc.sql("SELECT watch_queue_mode,watch_transition_seconds FROM rooms WHERE id=:r").param("r",roomId).query((rs,n)->new QueueSettings(rs.getString(1),rs.getInt(2))).single();
  List<NextVideo> candidates=nextCandidates(roomId);
  NextVideo next=(requested==null?pickNextVideo(candidates,u.id()):candidates.stream().filter(v->v.id().equals(requested)).findFirst()).orElseThrow(()->new ResponseStatusException(HttpStatus.NOT_FOUND,"The queue is empty"));if(!next.provider().equals("YOUTUBE"))throw new ResponseStatusException(HttpStatus.CONFLICT,next.provider()+" playback is not integrated yet");
  jdbc.sql("UPDATE room_watch_queue SET status='PLAYED' WHERE id=:id").param("id",next.id()).update();Instant starts=Instant.now().plus(Math.max(8,Math.min(10,settings.transitionSeconds())),ChronoUnit.SECONDS);saveState(roomId,u.id(),next.provider(),next.mediaId(),next.title(),true,0,1,starts);return state(jwt,roomId);
 }

 private List<NextVideo> nextCandidates(UUID roomId){return jdbc.sql("""
    SELECT q.id,q.provider,q.media_id,q.title,q.added_by,q.created_at,COUNT(v.user_id) votes
    FROM room_watch_queue q LEFT JOIN room_watch_votes v ON v.queue_id=q.id
    WHERE q.room_id=:r AND q.status='QUEUED' AND NOT EXISTS (SELECT 1 FROM room_watch_queue earlier WHERE earlier.room_id=q.room_id AND earlier.added_by=q.added_by AND earlier.status='QUEUED' AND (earlier.personal_position<q.personal_position OR (earlier.personal_position=q.personal_position AND earlier.created_at<q.created_at))) GROUP BY q.id ORDER BY q.created_at,q.id
    """).param("r",roomId).query((rs,n)->new NextVideo(rs.getObject("id",UUID.class),rs.getString("provider"),rs.getString("media_id"),rs.getString("title"),rs.getObject("added_by",UUID.class),rs.getTimestamp("created_at").toInstant(),rs.getInt("votes"))).list();}

 @PatchMapping("/rooms/{roomId}/watch/settings") void watchSettings(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@RequestBody WatchSettings x){CurrentUser u=users.synchronize(jwt);manager(roomId,u.id());String mode=x.mode()==null?"HOSTS_ONLY":x.mode().toUpperCase(Locale.ROOT);if(!List.of("HOSTS_ONLY","PERMISSION","VOTE").contains(mode))throw new ResponseStatusException(HttpStatus.BAD_REQUEST);jdbc.sql("UPDATE rooms SET watch_queue_mode=:m,watch_transition_seconds=:s WHERE id=:r").param("m",mode).param("s",Math.max(8,Math.min(10,x.transitionSeconds()))).param("r",roomId).update();}
 @PostMapping("/rooms/{roomId}/members/{userId}/video-permission") void videoPermission(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID roomId,@PathVariable UUID userId,@RequestBody Map<String,Boolean> body){CurrentUser u=users.synchronize(jwt);manager(roomId,u.id());jdbc.sql("UPDATE room_members SET can_add_videos=:a WHERE room_id=:r AND user_id=:u AND role <> 'HOST'").param("a",Boolean.TRUE.equals(body.get("allowed"))).param("r",roomId).param("u",userId).update();}

 @GetMapping("/youtube/search") SearchResponse search(@AuthenticationPrincipal Jwt jwt,@RequestParam("q") @Size(min=2,max=100) String q,@RequestParam(value="pageToken",required=false) @Size(max=200) String pageToken){
  users.synchronize(jwt);
  if(key.isBlank())return new SearchResponse(false,List.of(),"Set YOUTUBE_API_KEY to enable search. Paste a YouTube URL for now.",null,null);
  UriComponentsBuilder builder=UriComponentsBuilder.fromUriString("https://www.googleapis.com/youtube/v3/search")
    .queryParam("part","snippet").queryParam("type","video").queryParam("videoEmbeddable","true")
    .queryParam("safeSearch","moderate").queryParam("maxResults",12).queryParam("q",q.trim()).queryParam("key",key.trim());
  if(pageToken!=null&&!pageToken.isBlank())builder.queryParam("pageToken",pageToken.trim());
  JsonNode json=rest.get().uri(builder.build().encode().toUri()).retrieve().body(JsonNode.class);
  List<YoutubeResult> out=new ArrayList<>();
  if(json!=null)for(JsonNode i:json.path("items")){String id=i.path("id").path("videoId").asText();JsonNode s=i.path("snippet");if(!id.isBlank())out.add(new YoutubeResult(id,s.path("title").asText(),s.path("channelTitle").asText(),s.path("thumbnails").path("medium").path("url").asText()));}
  String next=json==null?"":json.path("nextPageToken").asText("");String previous=json==null?"":json.path("prevPageToken").asText("");
  return new SearchResponse(true,out,null,next.isBlank()?null:next,previous.isBlank()?null:previous);
 }

 private void saveState(UUID r,UUID u,String provider,String media,String title,boolean playing,double pos,double rate,Instant transition){jdbc.sql("""
   INSERT INTO room_watch_state(room_id,provider,media_id,title,playing,position_seconds,playback_rate,updated_at,updated_by,transition_until)
   VALUES(:r,:p,:m,:t,:playing,:pos,:rate,now(),:u,CAST(:transition AS TIMESTAMPTZ)) ON CONFLICT(room_id) DO UPDATE SET provider=EXCLUDED.provider,media_id=EXCLUDED.media_id,title=EXCLUDED.title,playing=EXCLUDED.playing,position_seconds=EXCLUDED.position_seconds,playback_rate=EXCLUDED.playback_rate,updated_at=now(),updated_by=EXCLUDED.updated_by,transition_until=EXCLUDED.transition_until
   """).param("r",r).param("p",provider).param("m",media).param("t",title).param("playing",playing).param("pos",Math.max(0,pos)).param("rate",rate<=0?1:rate).param("u",u).param("transition",transition==null?null:transition.toString()).update();}
 private void member(UUID r,UUID u){if(!jdbc.sql("SELECT EXISTS(SELECT 1 FROM room_members WHERE room_id=:r AND user_id=:u AND status='ACTIVE')").param("r",r).param("u",u).query(Boolean.class).single())throw new ResponseStatusException(HttpStatus.FORBIDDEN);}
 private void selectRoomVote(UUID roomId,UUID userId,UUID queueId){jdbc.sql("DELETE FROM room_watch_votes WHERE room_id=:r AND user_id=:u").param("r",roomId).param("u",userId).update();jdbc.sql("INSERT INTO room_watch_votes(room_id,queue_id,user_id) SELECT :r,id,:u FROM room_watch_queue WHERE id=:q AND room_id=:r AND status='QUEUED'").param("r",roomId).param("q",queueId).param("u",userId).update();}
 private String role(UUID r,UUID u){return jdbc.sql("SELECT role FROM room_members WHERE room_id=:r AND user_id=:u AND status='ACTIVE'").param("r",r).param("u",u).query(String.class).optional().orElseThrow(()->new ResponseStatusException(HttpStatus.FORBIDDEN));}
 private void manager(UUID r,UUID u){String role=role(r,u);if(!role.equals("HOST")&&!role.equals("CO_HOST"))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Only hosts control playback");}
 private void host(UUID r,UUID u){if(!role(r,u).equals("HOST"))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Only the room host controls playback");}
 private boolean canAdd(UUID r,UUID u){String role=role(r,u);if(role.equals("HOST")||role.equals("CO_HOST"))return true;return jdbc.sql("SELECT rooms.watch_queue_mode='VOTE' OR (rooms.watch_queue_mode='PERMISSION' AND rm.can_add_videos) FROM room_members rm JOIN rooms ON rooms.id=rm.room_id WHERE rm.room_id=:r AND rm.user_id=:u").param("r",r).param("u",u).query(Boolean.class).single();}
 private List<QueueItem> roomCandidates(List<QueueItem> items){Map<UUID,QueueItem> first=new LinkedHashMap<>();items.stream().sorted(Comparator.comparingInt(QueueItem::personalPosition).thenComparing(QueueItem::createdAt)).forEach(i->first.putIfAbsent(i.addedBy(),i));return first.values().stream().sorted(Comparator.comparingInt(QueueItem::voteCount).reversed().thenComparing(QueueItem::createdAt)).toList();}
 private SkipStatus skipStatus(UUID roomId,UUID userId){String media=jdbc.sql("SELECT media_id FROM room_watch_state WHERE room_id=:r").param("r",roomId).query(String.class).optional().orElse("");int active=jdbc.sql("SELECT COUNT(*) FROM room_live_presence WHERE room_id=:r AND last_seen_at>now()-interval '45 seconds'").param("r",roomId).query(Integer.class).single();int required=Math.max(1,(active/2)+1);if(media.isBlank())return new SkipStatus(0,required,false);return jdbc.sql("SELECT COUNT(*) votes,BOOL_OR(user_id=:u) voted FROM room_watch_skip_votes WHERE room_id=:r AND media_id=:m").param("u",userId).param("r",roomId).param("m",media).query((rs,n)->new SkipStatus(rs.getInt("votes"),required,rs.getBoolean("voted"))).single();}
 private Optional<QueueItem> pickNext(List<QueueItem> items,UUID user){if(items.isEmpty())return Optional.empty();QueueItem global=items.stream().max(Comparator.comparingInt(QueueItem::voteCount).thenComparing(QueueItem::createdAt,Comparator.reverseOrder())).orElseThrow();QueueItem mine=items.stream().filter(i->i.addedBy().equals(user)).min(Comparator.comparing(QueueItem::createdAt)).orElse(null);return Optional.of(mine!=null&&mine.voteCount()>=global.voteCount()?mine:global);}
 private Optional<NextVideo> pickNextVideo(List<NextVideo> items,UUID user){if(items.isEmpty())return Optional.empty();NextVideo global=items.stream().max(Comparator.comparingInt(NextVideo::votes).thenComparing(NextVideo::createdAt,Comparator.reverseOrder())).orElseThrow();NextVideo mine=items.stream().filter(i->i.addedBy().equals(user)).min(Comparator.comparing(NextVideo::createdAt)).orElse(null);return Optional.of(mine!=null&&mine.votes()>=global.votes()?mine:global);}

 public record WatchState(String provider,String mediaId,String title,boolean playing,double positionSeconds,double playbackRate,Instant updatedAt,Instant transitionUntil){}
 public record WatchUpdate(@NotBlank String provider,@NotBlank @Size(max=500) String mediaId,@Size(max=500) String title,boolean playing,double positionSeconds,double playbackRate){}
 public record YoutubeResult(String videoId,String title,String channelTitle,String thumbnailUrl){} public record SearchResponse(boolean configured,List<YoutubeResult> results,String message,String nextPageToken,String previousPageToken){}
 public record QueueAdd(@NotBlank String provider,@NotBlank @Size(max=500) String mediaId,@NotBlank @Size(max=500) String title,@Size(max=1000) String thumbnailUrl){}
 public record QueueItem(UUID id,String provider,String mediaId,String title,String thumbnailUrl,UUID addedBy,String addedByName,int personalPosition,int voteCount,boolean votedByMe,Instant createdAt){}
 public record QueueResponse(String mode,int transitionSeconds,boolean canAdd,UUID nextItemId,int skipVotes,int skipRequired,boolean skipVotedByMe,List<QueueItem> items){} public record QueueSettings(String mode,int transitionSeconds){} public record WatchSettings(String mode,int transitionSeconds){} public record NextRequest(UUID queueId){} public record ReorderRequest(List<UUID> queueIds){} public record SkipVoteResult(boolean skipped,int votes,int required,WatchState state){} private record SkipStatus(int votes,int required,boolean votedByMe){} private record NextVideo(UUID id,String provider,String mediaId,String title,UUID addedBy,Instant createdAt,int votes){}
}
