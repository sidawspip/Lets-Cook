package com.letscook.platform.search;

import static com.letscook.platform.search.SearchModels.*;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.CurrentUserService;
import jakarta.validation.constraints.Size;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Authenticated global search API.
 *
 * <p>Searches users and only those rooms the requesting user may discover. The query must
 * contain 2-80 characters; access filtering and ranking are delegated to {@link SearchService}.</p>
 */
@Validated
@RestController
@RequestMapping("/api/search")
public class SearchController {
    private final CurrentUserService currentUserService;
    private final SearchService searchService;

    public SearchController(CurrentUserService currentUserService, SearchService searchService) {
        this.currentUserService = currentUserService;
        this.searchService = searchService;
    }

    /** Searches users and discoverable rooms for a normalized 2-80 character query. */
    @GetMapping
    SearchResult search(@AuthenticationPrincipal Jwt jwt,
                        @RequestParam @Size(min = 2, max = 80) String q) {
        CurrentUser currentUser = currentUserService.synchronize(jwt);
        return searchService.search(currentUser.id(), q);
    }
}
