package com.letscook.platform.common;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Business rules for profiles, preferences, privacy, interests, connections, and avatars.
 *
 * <p>Normalizes visibility levels, validates language/reaction values and HTTPS connections,
 * limits profile collections, validates image signatures, and removes replaced local avatars.</p>
 */
@Service
class ProfileServiceImpl implements ProfileService {
    private static final long MAX_AVATAR_BYTES=5L*1024*1024;
    private static final Map<String,String> EXTENSIONS=Map.of("image/jpeg",".jpg","image/png",".png","image/webp",".webp","image/gif",".gif");
    private final ProfileRepository repository;
    private final Path avatarDirectory;
    ProfileServiceImpl(ProfileRepository repository,@Value("${app.uploads.avatar-directory:/app/uploads/avatars}") String avatarDirectory){this.repository=repository;this.avatarDirectory=Path.of(avatarDirectory).toAbsolutePath().normalize();}
    public ProfileModels.ProfileView profile(UUID userId){return repository.profile(userId);}
    public ProfileModels.ProfileView update(UUID userId,ProfileModels.UpdateProfile input){repository.update(userId,input);return repository.profile(userId);}
    public ProfileModels.ProfileDashboard dashboard(UUID userId){return new ProfileModels.ProfileDashboard(repository.profile(userId),repository.preferences(userId),repository.visibility(userId),repository.connections(userId),repository.interests(userId));}
    public Map<String,Object> publicProfile(UUID viewerId,UUID profileId){
        var target=repository.profile(profileId);boolean owner=viewerId.equals(profileId);boolean friend=owner||repository.areFriends(viewerId,profileId);boolean hideSensitive=repository.hideSensitiveContent(viewerId);var visibility=repository.visibility(profileId);Map<String,Object> result=new LinkedHashMap<>();
        result.put("id",target.id());result.put("username",PublicIdentity.handle(target.username(),target.id()));result.put("displayName",PublicIdentity.displayName(target.displayName(),target.username(),target.id()));result.put("avatarUrl",target.avatarUrl());
        result.put("online",repository.online(profileId));result.put("joinedAt",repository.createdAt(profileId));result.put("lastSeenAt",repository.lastSeenAt(profileId));result.put("sensitiveContentHidden",hideSensitive);
        result.put("relationship",owner?Map.of("status","SELF","outgoing",false):repository.relationship(viewerId,profileId));
        if(visible(visibility.bio(),owner,friend))result.put("bio",target.bio());
        if(visible(visibility.connections(),owner,friend))result.put("connections",repository.connections(profileId));
        if(visible(visibility.gallery(),owner,friend))result.put("gallery",repository.gallery(profileId,hideSensitive));
        if(visible(visibility.activity(),owner,friend)){result.put("activityByDay",repository.dailyActivity(profileId));result.put("history",repository.history(profileId,hideSensitive));result.put("likedVideos",repository.likes(profileId,hideSensitive));}
        if(visible(visibility.stats(),owner,friend)){result.put("watchTogetherSeconds",repository.watchSeconds(profileId));result.put("providerUsage",repository.providerUsage(profileId,hideSensitive));}
        if(visible(visibility.friends(),owner,friend)){result.put("friendCount",repository.friendCount(profileId));result.put("watchFriends",repository.watchFriends(profileId));}
        if(visible(visibility.interests(),owner,friend)){result.put("interests",repository.interests(profileId));result.put("inferredInterests",repository.inferredInterests(profileId,hideSensitive));}
        return result;
    }
    private boolean visible(String level,boolean owner,boolean friend){return owner||"PUBLIC".equals(level)||("FRIENDS".equals(level)&&friend);}
    public ProfileModels.ProfileVisibility updateVisibility(UUID userId,ProfileModels.ProfileVisibility input){var value=normalize(input);repository.updateVisibility(userId,value);return value;}
    private ProfileModels.ProfileVisibility normalize(ProfileModels.ProfileVisibility v){return new ProfileModels.ProfileVisibility(level(v.bio()),level(v.gallery()),level(v.activity()),level(v.stats()),level(v.friends()),level(v.interests()),level(v.connections()));}
    private String level(String value){String result=value==null?"PRIVATE":value.toUpperCase(Locale.ROOT);if(!List.of("PUBLIC","FRIENDS","PRIVATE").contains(result))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid profile visibility");return result;}
    public ProfileModels.Preferences updatePreferences(UUID userId,ProfileModels.PreferencesPatch input){String language=input.preferredLanguage()==null?null:input.preferredLanguage().trim().toLowerCase(Locale.ROOT);if(language!=null&&!language.matches("[a-z]{2,3}(-[a-z]{2})?"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid language");String reaction=input.quickReaction()==null?null:input.quickReaction().strip();if(reaction!=null&&(reaction.isEmpty()||reaction.codePointCount(0,reaction.length())>4))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid quick reaction");repository.updatePreferences(userId,input,language,reaction);return repository.preferences(userId);}
    @Transactional public void replaceConnections(UUID userId,List<ProfileModels.Connection> input){repository.deleteConnections(userId);input.stream().limit(10).forEach(value->{String provider=value.provider()==null?"":value.provider().trim().toUpperCase(Locale.ROOT);String url=value.url()==null?"":value.url().trim();if(!provider.matches("[A-Z0-9_]{2,40}")||!url.matches("https://.+"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Connections require an HTTPS URL");repository.addConnection(userId,new ProfileModels.Connection(provider,url));});}
    @Transactional public void replaceInterests(UUID userId,List<String> input){repository.deleteInterests(userId);input.stream().map(String::trim).filter(v->!v.isEmpty()).distinct().limit(20).forEach(value->{if(value.length()>60)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Interest is too long");repository.addInterest(userId,value);});}
    public ProfileModels.ProfileView uploadAvatar(UUID userId,MultipartFile file){
        if(file.isEmpty()||file.getSize()>MAX_AVATAR_BYTES)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Avatar must be a non-empty image up to 5 MB");String contentType=file.getContentType();String extension=EXTENSIONS.get(contentType);if(extension==null)throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"Use JPG, PNG, WebP, or GIF");
        try{byte[] bytes=file.getBytes();if(!validImageSignature(contentType,bytes))throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"The uploaded file is not a valid image");Files.createDirectories(avatarDirectory);String fileName=userId+"-"+UUID.randomUUID()+extension;Path target=avatarDirectory.resolve(fileName).normalize();if(!target.getParent().equals(avatarDirectory))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid filename");Files.write(target,bytes);String previous=repository.avatarUrl(userId);repository.updateAvatar(userId,"/api/me/avatar/"+fileName);deletePrevious(previous,fileName);return repository.profile(userId);}catch(IOException exception){throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"Could not store avatar",exception);}
    }
    public ProfileModels.StoredFile avatar(String fileName){if(!fileName.matches("[0-9a-fA-F-]+\\.(jpg|png|webp|gif)"))throw new ResponseStatusException(HttpStatus.NOT_FOUND);Path file=avatarDirectory.resolve(fileName).normalize();if(!file.getParent().equals(avatarDirectory)||!Files.isRegularFile(file))throw new ResponseStatusException(HttpStatus.NOT_FOUND);try{String type=Files.probeContentType(file);return new ProfileModels.StoredFile(file,type==null?"application/octet-stream":type);}catch(IOException e){throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"Could not read avatar",e);}}
    private void deletePrevious(String previous,String current){if(previous==null||!previous.startsWith("/api/me/avatar/"))return;String name=previous.substring(previous.lastIndexOf('/')+1);if(name.equals(current)||!name.matches("[0-9a-fA-F-]+\\.(jpg|png|webp|gif)"))return;try{Files.deleteIfExists(avatarDirectory.resolve(name).normalize());}catch(IOException ignored){}}
    private boolean validImageSignature(String type,byte[] b){return switch(type){case "image/jpeg"->b.length>=3&&(b[0]&255)==0xff&&(b[1]&255)==0xd8&&(b[2]&255)==0xff;case "image/png"->b.length>=8&&(b[0]&255)==0x89&&b[1]==0x50&&b[2]==0x4e&&b[3]==0x47&&b[4]==0x0d&&b[5]==0x0a&&b[6]==0x1a&&b[7]==0x0a;case "image/gif"->b.length>=6&&b[0]=='G'&&b[1]=='I'&&b[2]=='F'&&b[3]=='8'&&(b[4]=='7'||b[4]=='9')&&b[5]=='a';case "image/webp"->b.length>=12&&b[0]=='R'&&b[1]=='I'&&b[2]=='F'&&b[3]=='F'&&b[8]=='W'&&b[9]=='E'&&b[10]=='B'&&b[11]=='P';default->false;};}
}
