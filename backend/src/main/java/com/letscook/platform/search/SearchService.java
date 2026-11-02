package com.letscook.platform.search;

import static com.letscook.platform.search.SearchModels.*;

import java.util.UUID;

/**
 * Search use cases scoped to the requesting user's room visibility and membership.
 */
public interface SearchService {
    /** Returns matching users and access-filtered rooms for the normalized query. */
    SearchResult search(UUID currentUserId, String query);
}
