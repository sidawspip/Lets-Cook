package com.letscook.platform.room;

import static com.letscook.platform.room.WatchModels.*;
import static com.letscook.platform.room.WatchQueueModels.*;

import java.net.URI;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Business logic for revisioned synchronized playback.
 *
 * <p>Only the host may mutate playback; hosts/co-hosts manage queue policy. Commands are
 * idempotent by command ID, reject stale revisions, clamp seek/rate values, validate playable
 * providers, and broadcast accepted state through the room watch topic.</p>
 */
@Service
public class WatchServiceImpl implements WatchService {
    private static final List<String> BROWSER_PROVIDERS = List.of(
            "GOOGLE_DRIVE", "DROPBOX", "ONEDRIVE", "BOX", "NEXTCLOUD",
            "INTERNET_ARCHIVE", "X", "TWITCH", "VIMEO", "NETFLIX",
            "PRIME_VIDEO", "CRUNCHYROLL");
    private final WatchRepository repository;
    private final WatchQueueService queueService;
    private final LiveRoomService liveRoom;
    private final YoutubeCatalogRepository youtube;
    private final SimpMessagingTemplate events;

    public WatchServiceImpl(
            WatchRepository repository,
            WatchQueueService queueService,
            LiveRoomService liveRoom,
            YoutubeCatalogRepository youtube,
            SimpMessagingTemplate events) {
        this.repository = repository;
        this.queueService = queueService;
        this.liveRoom = liveRoom;
        this.youtube = youtube;
        this.events = events;
    }

    @Override
    @Transactional(readOnly = true)
    public WatchState state(UUID roomId, UUID userId) {
        requireMember(roomId, userId);
        return repository.state(roomId).orElse(null);
    }

    @Override
    @Transactional
    public WatchState update(UUID roomId, UUID userId, WatchUpdate input) {
        requireHost(roomId, userId);
        validateMedia(input.provider(), input.sourceUrl());
        WatchState previous=repository.state(roomId).orElse(null);
        repository.save(
                roomId, userId, input.provider(), input.sourceType(), input.mediaId(),
                input.sourceUrl(), input.title(), input.playing(), input.positionSeconds(),
                input.durationSeconds(), input.playbackRate(), null);
        WatchState result = repository.state(roomId).orElseThrow();
        if(previous==null||!java.util.Objects.equals(previous.mediaId(),result.mediaId())
                ||!java.util.Objects.equals(previous.provider(),result.provider()))
            liveRoom.recordVideoPlayed(roomId,userId,result.provider(),result.mediaId(),result.title());
        broadcast(roomId, new WatchEvent(result, null, userId));
        return result;
    }

    @Override
    @Transactional
    public void command(UUID roomId, UUID userId, WatchCommand command) {
        requireHost(roomId, userId);
        WatchState current = repository.state(roomId).orElse(null);
        if (command.commandId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "commandId is required");
        }
        if (repository.commandRevision(roomId, command.commandId()).isPresent()
                || (current != null && command.expectedRevision() != current.revision())) {
            broadcast(roomId, new WatchEvent(current, command.commandId(), userId));
            return;
        }
        if ("NEXT".equalsIgnoreCase(command.type())) {
            WatchState result = playNextInternal(roomId, userId, null);
            repository.saveCommand(roomId, command.commandId(), result.revision());
            broadcast(roomId, new WatchEvent(result, command.commandId(), userId));
            return;
        }

        CommandState next = applyCommand(current, command);
        repository.save(
                roomId, userId, next.provider(), next.sourceType(), next.mediaId(), next.sourceUrl(),
                next.title(), next.playing(), next.position(), next.duration(), next.rate(), null);
        WatchState result = repository.state(roomId).orElseThrow();
        if("LOAD".equalsIgnoreCase(command.type())&&(current==null||!java.util.Objects.equals(current.mediaId(),result.mediaId())
                ||!java.util.Objects.equals(current.provider(),result.provider())))
            liveRoom.recordVideoPlayed(roomId,userId,result.provider(),result.mediaId(),result.title());
        repository.saveCommand(roomId, command.commandId(), result.revision());
        broadcast(roomId, new WatchEvent(result, command.commandId(), userId));
    }

    @Override
    @Transactional
    public WatchState heartbeat(UUID roomId, UUID userId) {
        requireHost(roomId, userId);
        repository.heartbeat(roomId);
        return repository.state(roomId).orElse(null);
    }

    @Override
    @Transactional(readOnly = true)
    public QueueResponse queue(UUID roomId, UUID userId) {
        requireMember(roomId, userId);
        return queueService.queue(roomId, userId);
    }

    @Override
    @Transactional
    public QueueItem addQueue(UUID roomId, UUID userId, QueueAdd input) {
        requireMember(roomId, userId);
        return queueService.add(
                roomId, userId, input.provider(), input.mediaId(), input.title(), input.thumbnailUrl(),
                input.personalQueueItem() == null || input.personalQueueItem());
    }

    @Override
    @Transactional
    public void reorder(UUID roomId, UUID userId, List<UUID> queueIds) {
        requireMember(roomId, userId);
        queueService.reorder(roomId, userId, queueIds);
    }

    @Override
    @Transactional
    public SkipVoteResult skipVote(UUID roomId, UUID userId) {
        boolean hostSkip = "HOST".equals(role(roomId, userId));
        SkipStatus status = queueService.addSkipVote(roomId, userId);
        if (!hostSkip && status.votes() < status.required()) {
            return new SkipVoteResult(false, status.votes(), status.required(), null);
        }
        QueueSettings settings = queueService.settings(roomId);
        NextVideo next = queueService.takeNext(roomId, null).orElse(null);
        if (next == null) {
            repository.stop(roomId, userId);
            return new SkipVoteResult(
                    true, status.votes(), status.required(), repository.state(roomId).orElse(null));
        }
        Instant starts = Instant.now().plus(settings.transitionSeconds(), ChronoUnit.SECONDS);
        saveNext(roomId, userId, next, starts);
        liveRoom.recordVideoPlayed(roomId,userId,next.provider(),next.mediaId(),next.title());
        WatchState result = repository.state(roomId).orElseThrow();
        broadcast(roomId, new WatchEvent(result, null, userId));
        return new SkipVoteResult(true, status.votes(), status.required(), result);
    }

    @Override
    @Transactional
    public QueueResponse vote(UUID roomId, UUID userId, UUID queueId) {
        requireMember(roomId, userId);
        queueService.toggleVote(roomId, userId, queueId);
        return queueService.queue(roomId, userId);
    }

    @Override
    @Transactional
    public void removeQueue(UUID roomId, UUID userId, UUID queueId) {
        requireManager(roomId, userId);
        queueService.remove(roomId, queueId);
    }

    @Override
    @Transactional
    public WatchState playNext(UUID roomId, UUID userId, UUID requestedQueueId) {
        requireHost(roomId, userId);
        return playNextInternal(roomId, userId, requestedQueueId);
    }

    @Override
    @Transactional
    public void updateSettings(UUID roomId, UUID userId, WatchSettings input) {
        requireManager(roomId, userId);
        queueService.updateSettings(roomId, input.mode(), input.transitionSeconds());
    }

    @Override
    @Transactional
    public void updateVideoPermission(
            UUID roomId, UUID userId, UUID targetUserId, Map<String, Boolean> input) {
        requireManager(roomId, userId);
        queueService.updateVideoPermission(roomId, targetUserId, Boolean.TRUE.equals(input.get("allowed")));
    }

    @Override
    @Transactional
    public void requestVideoAccess(UUID roomId, UUID userId) {
        requireMember(roomId, userId);
        repository.requestVideoAccess(roomId, userId);
    }

    @Override
    @Transactional
    public void updateVideoAccess(
            UUID roomId, UUID userId, UUID targetUserId, Map<String, Boolean> input) {
        requireManager(roomId, userId);
        repository.setVideoAccess(roomId, targetUserId, Boolean.TRUE.equals(input.get("allowed")));
    }

    @Override
    public SearchResponse searchYoutube(String query, String pageToken) {
        return youtube.search(query, pageToken);
    }

    private WatchState playNextInternal(UUID roomId, UUID userId, UUID requestedQueueId) {
        NextVideo next = queueService.takeNext(roomId, requestedQueueId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.NOT_FOUND, "The queue is empty"));
        saveNext(roomId, userId, next, null);
        liveRoom.recordVideoPlayed(roomId,userId,next.provider(),next.mediaId(),next.title());
        WatchState result = repository.state(roomId).orElseThrow();
        broadcast(roomId, new WatchEvent(result, null, userId));
        return result;
    }

    private void saveNext(UUID roomId, UUID userId, NextVideo next, Instant transition) {
        String direct = next.provider().startsWith("DIRECT") || BROWSER_PROVIDERS.contains(next.provider())
                ? next.mediaId() : null;
        repository.save(
                roomId, userId, next.provider(), next.provider(), next.mediaId(), direct,
                next.title(), true, 0, null, 1, transition);
    }

    private CommandState applyCommand(WatchState current, WatchCommand command) {
        String provider = current == null ? null : current.provider();
        String sourceType = current == null ? null : current.sourceType();
        String mediaId = current == null ? null : current.mediaId();
        String sourceUrl = current == null ? null : current.sourceUrl();
        String title = current == null ? null : current.title();
        boolean playing = current != null && current.playing();
        double position = current == null ? 0 : current.positionSeconds();
        double rate = current == null ? 1 : current.playbackRate();
        Double duration = current == null ? null : current.durationSeconds();
        String type = command.type() == null ? "" : command.type().toUpperCase(Locale.ROOT);
        switch (type) {
            case "LOAD" -> {
                Media media = command.media();
                if (media == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "media is required");
                provider = media.provider();
                sourceType = media.sourceType();
                mediaId = media.mediaId();
                sourceUrl = media.sourceUrl();
                title = media.title();
                duration = media.durationSeconds();
                position = command.positionSeconds() == null ? 0 : command.positionSeconds();
                playing = false;
                validateMedia(provider, sourceUrl);
            }
            case "PLAY" -> playing = true;
            case "PAUSE" -> playing = false;
            case "SEEK" -> position = requiredPosition(command.positionSeconds());
            case "RATE" -> rate = Math.max(.25, Math.min(2,
                    command.playbackRate() == null ? 1 : command.playbackRate()));
            case "STOP" -> { playing = false; position = 0; }
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported watch command");
        }
        if (provider == null) throw new ResponseStatusException(HttpStatus.CONFLICT, "Nothing is loaded");
        return new CommandState(
                provider, sourceType, mediaId, sourceUrl, title, playing, position, duration, rate);
    }

    private void validateMedia(String provider, String sourceUrl) {
        String normalized = provider == null ? "" : provider.toUpperCase(Locale.ROOT);
        if (!List.of("YOUTUBE", "DIRECT_MP4", "DIRECT_HLS").contains(normalized)
                && !BROWSER_PROVIDERS.contains(normalized)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported provider");
        }
        if (!normalized.startsWith("DIRECT") && !BROWSER_PROVIDERS.contains(normalized)) return;
        try {
            URI uri = URI.create(sourceUrl);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
                throw new IllegalArgumentException();
            }
        } catch (Exception exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Provider media must use a valid HTTPS URL");
        }
    }

    private double requiredPosition(Double value) {
        if (value == null || !Double.isFinite(value)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "positionSeconds is required");
        }
        return Math.max(0, value);
    }

    private void requireMember(UUID roomId, UUID userId) {
        role(roomId, userId);
    }

    private void requireManager(UUID roomId, UUID userId) {
        String role = role(roomId, userId);
        if (!List.of("HOST", "CO_HOST").contains(role)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only hosts control playback");
        }
    }

    private void requireHost(UUID roomId, UUID userId) {
        if (!"HOST".equals(role(roomId, userId))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only the room host controls playback");
        }
    }

    private String role(UUID roomId, UUID userId) {
        return repository.role(roomId, userId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.FORBIDDEN));
    }

    private void broadcast(UUID roomId, WatchEvent event) {
        events.convertAndSend("/topic/rooms/" + roomId + "/watch", event);
    }

    private record CommandState(
            String provider, String sourceType, String mediaId, String sourceUrl, String title,
            boolean playing, double position, Double duration, double rate) {}
}
