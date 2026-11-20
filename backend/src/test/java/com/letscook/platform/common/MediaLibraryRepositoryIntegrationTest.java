package com.letscook.platform.common;

import java.sql.DriverManager;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;

import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "ROOM_TEST_DATABASE_URL", matches = ".+")
class MediaLibraryRepositoryIntegrationTest {
    @Test
    void pageOnlyHistoryUpdatesPreservePlaybackUntilARefreshedSourceArrives() throws Exception {
        try (var connection = DriverManager.getConnection(System.getenv("ROOM_TEST_DATABASE_URL"),
                System.getenv("ROOM_TEST_DATABASE_USER"), System.getenv("ROOM_TEST_DATABASE_PASSWORD"))) {
            connection.setAutoCommit(false);
            try {
                var jdbc = JdbcClient.create(new SingleConnectionDataSource(connection, true));
                String schema = "media_test_" + UUID.randomUUID().toString().replace("-", "");
                jdbc.sql("CREATE SCHEMA " + schema).update();
                jdbc.sql("SET LOCAL search_path TO " + schema).update();
                jdbc.sql("CREATE TABLE app_users(id uuid PRIMARY KEY); CREATE TABLE rooms(id uuid PRIMARY KEY)").update();
                for (String migration : List.of("V15__user_media_library.sql", "V23__independent_media_history.sql",
                        "V30__history_playback_source_type.sql")) {
                    ScriptUtils.executeSqlScript(connection, new ClassPathResource("db/migration/" + migration));
                }
                UUID user = UUID.randomUUID();
                jdbc.sql("INSERT INTO app_users(id) VALUES(:id)").param("id", user).update();
                var repository = new MediaLibraryRepository(jdbc);
                String page = "https://watch.example/videos/123";
                String first = "https://cdn.example/video.mp4?signature=first";
                String refreshed = "https://cdn.example/master.m3u8?signature=refreshed";
                repository.upsert(user, page, "WEB", "Recorded video", null, first, false, 2, "DIRECT_MP4");
                repository.setLiked(user, page, true);

                repository.upsert(user, page, "WEB", "Legacy client", null, page, false, 1, null);
                assertThat(repository.history(user, 5)).singleElement().satisfies(item -> {
                    assertThat(item.provider()).isEqualTo("WEB");
                    assertThat(item.mediaId()).isEqualTo(page);
                    assertThat(item.sourceUrl()).isEqualTo(first);
                    assertThat(item.sourceType()).isEqualTo("DIRECT_MP4");
                });
                repository.upsert(user, page, "WEB", "Page only", null, page, false, 1, "WEB");
                assertThat(repository.item(user, page).sourceUrl()).isEqualTo(first);

                repository.upsert(user, page, "WEB", "Refreshed video", null, refreshed, false, 3, "DIRECT_HLS");
                assertThat(repository.likes(user, 5)).singleElement().satisfies(item -> {
                    assertThat(item.mediaId()).isEqualTo(page);
                    assertThat(item.sourceUrl()).isEqualTo(refreshed);
                    assertThat(item.sourceType()).isEqualTo("DIRECT_HLS");
                    assertThat(item.liked()).isTrue();
                    assertThat(item.playCount()).isEqualTo(4);
                });
            } finally {
                connection.rollback();
            }
        }
    }
}
