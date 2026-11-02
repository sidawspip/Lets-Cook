package com.letscook.platform.search;

import static com.letscook.platform.search.SearchModels.*;

import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * Business logic for normalized user and room search.
 * Results are access-filtered in the repository and returned as a combined search response.
 */
@Service
public class SearchServiceImpl implements SearchService {
    private final SearchRepository repository;

    public SearchServiceImpl(SearchRepository repository) {
        this.repository = repository;
    }

    @Override
    public SearchResult search(UUID currentUserId, String query) {
        String normalized = query.trim();
        String term = "%" + normalized + "%";
        return new SearchResult(
                repository.users(currentUserId, term, normalized),
                repository.rooms(currentUserId, term, normalized),
                List.of());
    }
}
