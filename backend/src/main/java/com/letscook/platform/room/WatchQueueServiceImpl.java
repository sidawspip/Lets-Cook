package com.letscook.platform.room;

import static com.letscook.platform.room.WatchQueueModels.*;

import java.net.URI;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Business rules for queue policy and ranking; SQL remains isolated in {@link WatchQueueRepository}.
 *
 * <p>Deduplicates active items by room/provider/media, treats repeat selection as a vote,
 * validates provider URLs, restricts adding by queue mode, requires complete personal lists
 * for reordering, and selects the highest-ranked playable next item.</p>
 */
@Service
public class WatchQueueServiceImpl implements WatchQueueService {
    private static final Set<String> QUEUE_PROVIDERS = Set.of(
            "YOUTUBE", "DIRECT_MP4", "DIRECT_HLS", "GOOGLE_DRIVE", "DROPBOX",
            "ONEDRIVE", "BOX", "NEXTCLOUD", "INTERNET_ARCHIVE", "X", "VIMEO",
            "NETFLIX", "PRIME_VIDEO", "CRUNCHYROLL", "TWITCH");
    private static final Set<String> PLAYABLE_PROVIDERS = Set.of(
            "YOUTUBE", "DIRECT_MP4", "DIRECT_HLS", "GOOGLE_DRIVE", "DROPBOX",
            "ONEDRIVE", "BOX", "NEXTCLOUD", "INTERNET_ARCHIVE", "X", "VIMEO",
            "NETFLIX", "PRIME_VIDEO", "CRUNCHYROLL", "TWITCH");
    private static final Set<String> QUEUE_MODES = Set.of(
            "HOSTS_ONLY", "PERMISSION", "VOTE");

    private final WatchQueueRepository repository;

    public WatchQueueServiceImpl(WatchQueueRepository repository) {
        this.repository = repository;
    }

    @Override
    @Transactional(readOnly = true)
    public QueueResponse queue(UUID roomId, UUID userId) {
        QueueSettings settings = repository.settings(roomId);
        List<QueueItem> items = repository.queuedItems(roomId, userId);
        SkipStatus skip = skipStatus(roomId, userId);
        UUID nextItemId = repository.nextCandidates(roomId).stream()
                .findFirst()
                .map(NextVideo::id)
                .orElse(null);
        return new QueueResponse(
                settings.mode(),
                settings.transitionSeconds(),
                repository.canAdd(roomId, userId),
                nextItemId,
                skip.votes(),
                skip.required(),
                skip.votedByMe(),
                items);
    }

    @Override
    @Transactional
    public QueueItem add(
            UUID roomId,
            UUID userId,
            String rawProvider,
            String rawMediaId,
            String rawTitle,
            String thumbnailUrl,
            boolean personalQueueItem) {
        if (!repository.canAdd(roomId, userId)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "The host has not allowed you to add videos");
        }
        String provider = rawProvider.trim().toUpperCase(Locale.ROOT);
        String mediaId = rawMediaId.trim();
        String title = rawTitle.trim();
        if (!QUEUE_PROVIDERS.contains(provider)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported provider");
        }
        if (!provider.equals("YOUTUBE")) validateHttpsMedia(mediaId);
        if (repository.isCurrentMedia(roomId, provider, mediaId)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This video is already playing");
        }

        Optional<UUID> existing = repository.queuedItemId(roomId, provider, mediaId);
        if (existing.isPresent()) {
            repository.selectVote(roomId, userId, existing.get());
            return item(roomId, userId, existing.get());
        }

        UUID id = UUID.randomUUID();
        int position = repository.nextPersonalPosition(roomId, userId);
        boolean inserted = repository.insert(
                id, roomId, provider, mediaId, title, thumbnailUrl, userId, position,
                personalQueueItem);
        UUID selected = inserted
                ? id
                : repository.queuedItemId(roomId, provider, mediaId).orElseThrow();
        if (!inserted || !personalQueueItem || position == 0) {
            repository.selectVote(roomId, userId, selected);
        }
        return item(roomId, userId, selected);
    }

    @Override
    @Transactional
    public void reorder(UUID roomId, UUID userId, List<UUID> queueIds) {
        List<UUID> ids = queueIds == null ? List.of() : List.copyOf(queueIds);
        Set<UUID> owned = repository.ownedQueueIds(roomId, userId);
        if (ids.size() != owned.size() || !owned.equals(new HashSet<>(ids))) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Reorder must contain your complete queue");
        }
        for (int index = 0; index < ids.size(); index++) {
            repository.updatePosition(roomId, userId, ids.get(index), index);
        }
    }

    @Override
    @Transactional
    public void toggleVote(UUID roomId, UUID userId, UUID queueId) {
        if (!repository.queuedItemExists(roomId, queueId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Queue item not found");
        }
        if (repository.hasVote(queueId, userId)) {
            repository.deleteVote(queueId, userId);
            return;
        }
        repository.selectVote(roomId, userId, queueId);
    }

    @Override
    @Transactional
    public void remove(UUID roomId, UUID queueId) {
        repository.deleteQueueItem(roomId, queueId);
    }

    @Override
    @Transactional
    public SkipStatus addSkipVote(UUID roomId, UUID userId) {
        String mediaId = repository.currentMediaId(roomId).orElseThrow(() ->
                new ResponseStatusException(HttpStatus.CONFLICT, "Nothing is playing"));
        repository.addSkipVote(roomId, mediaId, userId);
        return repository.skipStatus(roomId, mediaId, userId);
    }

    @Override
    @Transactional
    public Optional<NextVideo> takeNext(UUID roomId, UUID requestedQueueId) {
        List<NextVideo> candidates = repository.nextCandidates(roomId);
        Optional<NextVideo> selected = requestedQueueId == null
                ? candidates.stream().findFirst()
                : candidates.stream().filter(item -> item.id().equals(requestedQueueId)).findFirst();
        selected.ifPresent(item -> {
            if (!PLAYABLE_PROVIDERS.contains(item.provider())) {
                throw new ResponseStatusException(
                        HttpStatus.CONFLICT, item.provider() + " playback is not integrated yet");
            }
            repository.markPlayed(item.id());
            repository.firstQueuedItemForUser(roomId, item.addedBy())
                    .ifPresent(nextId -> repository.selectVote(roomId, item.addedBy(), nextId));
        });
        return selected;
    }

    @Override
    @Transactional(readOnly = true)
    public QueueSettings settings(UUID roomId) {
        return repository.settings(roomId);
    }

    @Override
    @Transactional
    public void updateSettings(UUID roomId, String rawMode, int transitionSeconds) {
        String mode = rawMode == null ? "HOSTS_ONLY" : rawMode.toUpperCase(Locale.ROOT);
        if (!QUEUE_MODES.contains(mode)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported queue mode");
        }
        repository.updateSettings(roomId, mode, Math.max(8, Math.min(10, transitionSeconds)));
    }

    @Override
    @Transactional
    public void updateVideoPermission(UUID roomId, UUID userId, boolean allowed) {
        repository.updateVideoPermission(roomId, userId, allowed);
    }

    private QueueItem item(UUID roomId, UUID userId, UUID queueId) {
        return repository.queuedItems(roomId, userId).stream()
                .filter(value -> value.id().equals(queueId))
                .findFirst()
                .orElseThrow();
    }

    private SkipStatus skipStatus(UUID roomId, UUID userId) {
        return repository.skipStatus(
                roomId, repository.currentMediaId(roomId).orElse(""), userId);
    }

    private void validateHttpsMedia(String value) {
        try {
            URI uri = URI.create(value);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
                throw new IllegalArgumentException();
            }
        } catch (Exception exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Provider media must use a valid HTTPS URL");
        }
    }
}
