package com.letscook.platform.room;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

import com.letscook.platform.room.WatchQueueModels.NextVideo;

class WatchQueueServiceImplTest {
    @Test
    void selectingANewCardReplacesTheUsersExistingRoomVote() {
        WatchQueueRepository repository = mock(WatchQueueRepository.class);
        WatchQueueServiceImpl service = new WatchQueueServiceImpl(repository);
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID queueId = UUID.randomUUID();
        when(repository.queuedItemExists(roomId, queueId)).thenReturn(true);
        when(repository.hasVote(queueId, userId)).thenReturn(false);

        service.toggleVote(roomId, userId, queueId);

        verify(repository).selectVote(roomId, userId, queueId);
        verify(repository, never()).deleteVote(queueId, userId);
    }

    @Test
    void selectingTheSameCardAgainRemovesTheVote() {
        WatchQueueRepository repository = mock(WatchQueueRepository.class);
        WatchQueueServiceImpl service = new WatchQueueServiceImpl(repository);
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID queueId = UUID.randomUUID();
        when(repository.queuedItemExists(roomId, queueId)).thenReturn(true);
        when(repository.hasVote(queueId, userId)).thenReturn(true);

        service.toggleVote(roomId, userId, queueId);

        verify(repository).deleteVote(queueId, userId);
        verify(repository, never()).selectVote(roomId, userId, queueId);
    }

    @Test
    void authenticatedProviderPageCanBecomeTheNextRoomItem() {
        WatchQueueRepository repository = mock(WatchQueueRepository.class);
        WatchQueueServiceImpl service = new WatchQueueServiceImpl(repository);
        UUID roomId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID queueId = UUID.randomUUID();
        NextVideo next = new NextVideo(
                queueId,
                "NETFLIX",
                "https://www.netflix.com/watch/123",
                "https://www.netflix.com/watch/123",
                "Selected title",
                userId,
                Instant.now(),
                1);
        when(repository.nextCandidates(roomId)).thenReturn(List.of(next));
        when(repository.firstQueuedItemForUser(roomId, userId)).thenReturn(Optional.empty());

        service.takeNext(roomId, queueId);

        verify(repository).markPlayed(queueId);
    }
}
