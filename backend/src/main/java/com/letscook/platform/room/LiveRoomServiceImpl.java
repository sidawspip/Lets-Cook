package com.letscook.platform.room;

import static com.letscook.platform.room.LiveRoomModels.*;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.PublicIdentity;
import java.time.Instant;
import java.util.List;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Business rules for an active room session.
 *
 * <p>Requires active membership, refreshes presence through heartbeats, tracks session duration,
 * supports host succession, session-scoped timeline events, replies, reactions, targeted mentions,
 * limits recent people, and clears ephemeral chat when a party empties.</p>
 */
@Service
public class LiveRoomServiceImpl implements LiveRoomService {
    private static final Pattern MENTION = Pattern.compile("(?<![A-Za-z0-9_])@([A-Za-z0-9_.-]{1,80})");
    private static final Set<String> REACTIONS = Set.of("❤️","🔥","😂","😍","👏","😮","😢","👍");
    private final LiveRoomRepository repository;
    private final SimpMessagingTemplate events;

    public LiveRoomServiceImpl(LiveRoomRepository repository,SimpMessagingTemplate events) {
        this.repository = repository;
        this.events = events;
    }

    @Override
    @Transactional
    public void join(UUID roomId, CurrentUser user) {
        requireMember(roomId, user.id());
        cleanup(roomId);
        repository.upsertPresence(roomId, user.id());
        repository.clearEmptySince(roomId);
        if(repository.startSession(UUID.randomUUID(), roomId, user.id())) {
            UUID messageId=UUID.randomUUID();
            repository.insertSystemEvent(messageId,roomId,user.id(),"joined the room","JOIN",Instant.now());
            publishTimeline(roomId,"JOIN",messageId);
        }
    }

    @Override
    @Transactional
    public void heartbeat(UUID roomId, UUID userId) {
        repository.touchPresence(roomId, userId);
        cleanup(roomId);
    }

    @Override
    @Transactional
    public void leave(UUID roomId, UUID userId) {
        if(repository.finishSession(roomId, userId)) {
            UUID messageId=UUID.randomUUID();
            repository.insertSystemEvent(messageId,roomId,userId,"left the room","LEAVE",Instant.now());
            publishTimeline(roomId,"LEAVE",messageId);
        }
        repository.deletePresence(roomId, userId);
        rebalanceLeadership(roomId);
        clearIfEmpty(roomId);
    }

    @Override
    @Transactional
    public List<Participant> participants(UUID roomId, UUID viewerId) {
        requireMember(roomId, viewerId);
        cleanup(roomId);
        List<Participant> participants = repository.participants(roomId).stream()
                .map(item -> new Participant(item.userId(), PublicIdentity.handle(item.username(), item.userId()),
                        PublicIdentity.displayName(item.displayName(), item.username(), item.userId()), item.avatarUrl(), item.role(), item.canShareScreen(), item.canAddVideos(), item.canViewVideo(), item.videoAccessRequested()))
                .toList();
        repository.rememberRecentPeople(roomId, viewerId);
        return participants;
    }

    @Override
    @Transactional(readOnly = true)
    public List<RecentPerson> recentPeople(UUID roomId, UUID viewerId) {
        requireMember(roomId, viewerId);
        return repository.recentPeople(viewerId).stream()
                .map(item -> new RecentPerson(item.userId(), PublicIdentity.handle(item.username(), item.userId()),
                        PublicIdentity.displayName(item.displayName(), item.username(), item.userId()), item.avatarUrl(), item.roomName(), item.lastSeenAt(), item.friend()))
                .toList();
    }

    @Override
    @Transactional
    public List<ChatMessage> messages(UUID roomId, UUID userId) {
        requirePresent(roomId, userId);
        cleanup(roomId);
        return repository.messages(roomId,userId).stream().map(this::publicMessage).toList();
    }

    @Override
    @Transactional
    public ChatMessage send(UUID roomId, CurrentUser user, SendChat input) {
        requirePresent(roomId, user.id());
        UUID id = UUID.randomUUID();
        Instant now = Instant.now();
        String body = input.body().trim();
        UUID replyTo=input.replyToId();
        if(replyTo!=null&&!repository.messageExists(roomId,replyTo)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Reply message is not in this room");
        }
        repository.insertMessage(id, roomId, user.id(), body, replyTo, now);
        notifyMentions(roomId,user,id,body);
        ChatMessage message=repository.messages(roomId,user.id()).stream().filter(item->item.id().equals(id)).map(this::publicMessage).findFirst().orElseThrow();
        publishTimeline(roomId,"MESSAGE",id);
        return message;
    }

    @Override
    @Transactional
    public ChatMessage shareVideo(UUID roomId, CurrentUser user, ShareVideo input) {
        requirePresent(roomId, user.id());
        UUID id = UUID.randomUUID();
        repository.insertVideoEvent(
                id,
                roomId,
                user.id(),
                input.provider().strip().toUpperCase(Locale.ROOT),
                input.mediaId().strip(),
                input.title().strip(),
                Instant.now());
        ChatMessage message = repository.messages(roomId, user.id()).stream()
                .filter(item -> item.id().equals(id))
                .map(this::publicMessage)
                .findFirst()
                .orElseThrow();
        publishTimeline(roomId, "VIDEO", id);
        return message;
    }

    @Override
    @Transactional
    public ChatMessage toggleReaction(UUID roomId,UUID userId,UUID messageId,String rawReaction) {
        requirePresent(roomId,userId);
        if(!repository.messageExists(roomId,messageId))throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Room message not found");
        String reaction=rawReaction==null?"":rawReaction.strip();
        if(!REACTIONS.contains(reaction))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Unsupported reaction");
        if(repository.hasReaction(messageId,userId,reaction))repository.deleteReaction(messageId,userId,reaction);
        else repository.addReaction(messageId,userId,reaction);
        ChatMessage message=repository.messages(roomId,userId).stream().filter(item->item.id().equals(messageId)).map(this::publicMessage).findFirst().orElseThrow();
        publishTimeline(roomId,"REACTION",messageId);
        return message;
    }

    @Override
    @Transactional
    public void recordVideoPlayed(UUID roomId,UUID actorId,String provider,String mediaId,String title) {
        if(!repository.isPresent(roomId,actorId))return;
        String safeTitle=title==null||title.isBlank()?"a video":title.strip();
        UUID messageId=UUID.randomUUID();
        repository.insertVideoEvent(messageId,roomId,actorId,
                provider==null?"UNKNOWN":provider.toUpperCase(Locale.ROOT),mediaId,safeTitle,Instant.now());
        publishTimeline(roomId,"VIDEO",messageId);
    }

    @Scheduled(fixedDelayString = "PT1M")
    @Transactional
    public void cleanupAllStaleSessions() {
        repository.finishAllStaleSessions();
    }

    private void cleanup(UUID roomId) {
        for(UUID staleUser:repository.stalePresenceUserIds(roomId)) {
            if(repository.finishStaleSession(roomId,staleUser)) {
                UUID messageId=UUID.randomUUID();
                repository.insertSystemEvent(messageId,roomId,staleUser,"left the room","LEAVE",Instant.now());
                publishTimeline(roomId,"LEAVE",messageId);
            }
        }
        repository.deleteStalePresence(roomId);
        rebalanceLeadership(roomId);
        clearIfEmpty(roomId);
    }

    private void clearIfEmpty(UUID roomId) {
        if (!repository.isEmpty(roomId)) return;
        if (repository.isEphemeral(roomId)) repository.markEmpty(roomId);
        repository.deleteMessages(roomId);
    }

    private void rebalanceLeadership(UUID roomId) {
        if (repository.hostPresent(roomId)) return;
        repository.nextLeader(roomId).ifPresent(userId -> repository.promoteLeader(roomId, userId));
    }

    private void requireMember(UUID roomId, UUID userId) {
        if (!repository.isActiveMember(roomId, userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Active room membership required");
        }
    }

    private void requirePresent(UUID roomId, UUID userId) {
        if (!repository.isPresent(roomId, userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Join the live room before chatting");
        }
    }

    private void notifyMentions(UUID roomId,CurrentUser sender,UUID messageId,String body) {
        Matcher matcher=MENTION.matcher(body);Set<String> usernames=new LinkedHashSet<>();
        while(matcher.find()&&usernames.size()<8)usernames.add(matcher.group(1).toLowerCase(Locale.ROOT));
        for(String username:usernames)repository.activeMentionTarget(roomId,username)
                .filter(target->!target.userId().equals(sender.id())&&target.subject()!=null&&!target.subject().isBlank())
                .ifPresent(target->events.convertAndSendToUser(target.subject(),"/queue/notifications",
                        new MentionEvent("ROOM_MENTION",sender.id(),sender.displayName(),body,roomId,messageId,target.hapticFeedback())));
    }

    private void publishTimeline(UUID roomId,String action,UUID messageId) {
        events.convertAndSend("/topic/rooms/"+roomId+"/chat",new TimelineChanged(roomId,action,messageId));
    }

    private ChatMessage publicMessage(ChatMessage message) {
        ReplyPreview reply = message.replyTo();
        ReplyPreview publicReply = reply == null ? null : new ReplyPreview(
                reply.id(), reply.senderId(), reply.senderName(),
                PublicIdentity.handle(reply.senderUsername(), reply.senderId()), reply.body(), reply.type());
        return new ChatMessage(message.id(), message.senderId(), message.senderName(),
                PublicIdentity.handle(message.senderUsername(), message.senderId()), message.avatarUrl(),
                message.body(), message.type(), publicReply, message.reactions(), message.mediaProvider(),
                message.mediaId(), message.mediaTitle(), message.createdAt());
    }
}
