package com.letscook.platform.common;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/me")
public class ProfileController {
    private final CurrentUserService currentUserService;
    private final JdbcClient jdbc;
    private final Path avatarDirectory;
    private static final long MAX_AVATAR_BYTES = 5L * 1024 * 1024;
    private static final Map<String,String> EXTENSIONS = Map.of(
            "image/jpeg", ".jpg", "image/png", ".png", "image/webp", ".webp", "image/gif", ".gif");

    public ProfileController(CurrentUserService currentUserService, JdbcClient jdbc,
                             @Value("${app.uploads.avatar-directory:/app/uploads/avatars}") String avatarDirectory) {
        this.currentUserService = currentUserService;
        this.jdbc = jdbc;
        this.avatarDirectory = Path.of(avatarDirectory).toAbsolutePath().normalize();
    }

    @GetMapping
    CurrentUser me(@AuthenticationPrincipal Jwt jwt) {
        return currentUserService.synchronize(jwt);
    }

    @GetMapping("/profile")
    ProfileView profile(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user=currentUserService.synchronize(jwt);
        return read(user.id());
    }

    @PatchMapping("/profile")
    ProfileView update(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody UpdateProfile input) {
        CurrentUser user=currentUserService.synchronize(jwt);
        jdbc.sql("UPDATE app_users SET display_name=COALESCE(:name,display_name), bio=COALESCE(:bio,bio), updated_at=now() WHERE id=:id")
                .param("name",input.displayName()).param("bio",input.bio()).param("id",user.id()).update();
        return read(user.id());
    }

    @PostMapping(value="/avatar", consumes=MediaType.MULTIPART_FORM_DATA_VALUE)
    ProfileView uploadAvatar(@AuthenticationPrincipal Jwt jwt, @RequestParam("file") MultipartFile file) {
        CurrentUser user=currentUserService.synchronize(jwt);
        if (file.isEmpty() || file.getSize() > MAX_AVATAR_BYTES) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Avatar must be a non-empty image up to 5 MB");
        }
        String contentType=file.getContentType();
        String extension=EXTENSIONS.get(contentType);
        if(extension==null) throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"Use JPG, PNG, WebP, or GIF");
        try {
            byte[] bytes=file.getBytes();
            if(!validImageSignature(contentType,bytes)) {
                throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"The uploaded file is not a valid image");
            }
            Files.createDirectories(avatarDirectory);
            String fileName=user.id()+"-"+UUID.randomUUID()+extension;
            Path target=avatarDirectory.resolve(fileName).normalize();
            if(!target.getParent().equals(avatarDirectory)) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid filename");
            Files.write(target,bytes);
            String previous=jdbc.sql("SELECT avatar_url FROM app_users WHERE id=:id").param("id",user.id()).query(String.class).optional().orElse(null);
            String avatarUrl="/api/me/avatar/"+fileName;
            jdbc.sql("UPDATE app_users SET avatar_url=:avatar,updated_at=now() WHERE id=:id")
                    .param("avatar",avatarUrl).param("id",user.id()).update();
            deletePreviousLocalAvatar(previous,fileName);
            return read(user.id());
        } catch(IOException exception) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"Could not store avatar",exception);
        }
    }

    @GetMapping("/avatar/{fileName:.+}")
    ResponseEntity<FileSystemResource> avatar(@PathVariable String fileName) throws IOException {
        if(!fileName.matches("[0-9a-fA-F-]+\\.(jpg|png|webp|gif)")) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        Path file=avatarDirectory.resolve(fileName).normalize();
        if(!file.getParent().equals(avatarDirectory) || !Files.isRegularFile(file)) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        String contentType=Files.probeContentType(file);
        return ResponseEntity.ok().cacheControl(CacheControl.noCache()).contentType(MediaType.parseMediaType(contentType==null?"application/octet-stream":contentType)).body(new FileSystemResource(file));
    }

    private void deletePreviousLocalAvatar(String previous,String currentFileName) {
        if(previous==null || !previous.startsWith("/api/me/avatar/")) return;
        String previousName=previous.substring(previous.lastIndexOf('/')+1);
        if(previousName.equals(currentFileName) || !previousName.matches("[0-9a-fA-F-]+\\.(jpg|png|webp|gif)")) return;
        try { Files.deleteIfExists(avatarDirectory.resolve(previousName).normalize()); } catch(IOException ignored) { }
    }

    private boolean validImageSignature(String contentType,byte[] bytes) {
        return switch(contentType) {
            case "image/jpeg" -> bytes.length>=3 && (bytes[0]&255)==0xff && (bytes[1]&255)==0xd8 && (bytes[2]&255)==0xff;
            case "image/png" -> bytes.length>=8 && (bytes[0]&255)==0x89 && bytes[1]==0x50 && bytes[2]==0x4e && bytes[3]==0x47
                    && bytes[4]==0x0d && bytes[5]==0x0a && bytes[6]==0x1a && bytes[7]==0x0a;
            case "image/gif" -> bytes.length>=6 && bytes[0]=='G' && bytes[1]=='I' && bytes[2]=='F' && bytes[3]=='8'
                    && (bytes[4]=='7'||bytes[4]=='9') && bytes[5]=='a';
            case "image/webp" -> bytes.length>=12 && bytes[0]=='R' && bytes[1]=='I' && bytes[2]=='F' && bytes[3]=='F'
                    && bytes[8]=='W' && bytes[9]=='E' && bytes[10]=='B' && bytes[11]=='P';
            default -> false;
        };
    }

    private ProfileView read(UUID id) {
        return jdbc.sql("SELECT id,username,display_name,email,bio,avatar_url FROM app_users WHERE id=:id").param("id",id)
                .query((rs,n)->new ProfileView(rs.getObject("id",UUID.class),rs.getString("username"),rs.getString("display_name"),
                        rs.getString("email"),rs.getString("bio"),rs.getString("avatar_url"))).single();
    }

    public record UpdateProfile(@Size(max=120) String displayName,@Size(max=500) String bio) {}
    public record ProfileView(UUID id,String username,String displayName,String email,String bio,String avatarUrl) {}
}

