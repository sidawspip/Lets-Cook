package com.letscook.platform.social;

import com.letscook.platform.common.CurrentUser;
import com.letscook.platform.common.PublicIdentity;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

/**
 * Business rules for friends, requests, blocks, and direct messaging.
 *
 * <p>Prevents self-actions, respects two-way blocks and invite restrictions, requires an
 * accepted friendship for DMs, validates attachment size/signature, and emits targeted
 * ephemeral STOMP notifications after persistent messages are stored.</p>
 */
@Service
class SocialServiceImpl implements SocialService {
    private static final long MAX_IMAGE_BYTES=8L*1024*1024,MAX_VIDEO_BYTES=25L*1024*1024;
    private final SocialRepository repository;private final SimpMessagingTemplate events;private final Path messageDirectory;
    SocialServiceImpl(SocialRepository repository,SimpMessagingTemplate events,@Value("${app.uploads.message-directory:/app/uploads/messages}") String directory){this.repository=repository;this.events=events;this.messageDirectory=Path.of(directory).toAbsolutePath().normalize();}
    public List<SocialModels.Friend> friends(UUID userId){return repository.friends(userId).stream().map(item->new SocialModels.Friend(item.id(),PublicIdentity.handle(item.username(),item.id()),PublicIdentity.displayName(item.displayName(),item.username(),item.id()),item.avatarUrl(),item.online(),item.watchTogetherSeconds())).toList();}
    public List<SocialModels.FriendRequest> requests(UUID userId){return repository.requests(userId).stream().map(item->new SocialModels.FriendRequest(item.id(),item.userId(),PublicIdentity.handle(item.username(),item.userId()),PublicIdentity.displayName(item.displayName(),item.username(),item.userId()))).toList();}
    public List<SocialModels.Notification> notifications(UUID userId){List<SocialModels.Notification> result=new ArrayList<>(repository.requestNotifications(userId));result.addAll(repository.messageNotifications(userId));result=result.stream().map(item->new SocialModels.Notification(item.id(),item.type(),item.userId(),PublicIdentity.handle(item.username(),item.userId()),item.displayName(),item.body(),item.unreadCount(),item.createdAt())).collect(java.util.stream.Collectors.toCollection(ArrayList::new));result.sort(Comparator.comparing(SocialModels.Notification::createdAt).reversed());return result;}
    public void request(UUID userId,UUID targetId){if(userId.equals(targetId))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"You cannot friend yourself");if(repository.blockedBetween(userId,targetId))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Friend requests are unavailable for this user");try{repository.createRequest(UUID.randomUUID(),userId,targetId);}catch(RuntimeException ex){throw new ResponseStatusException(HttpStatus.CONFLICT,"Friend request already exists");}}
    public void removeFriend(UUID userId,UUID targetId){if(userId.equals(targetId))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"You cannot remove yourself");repository.removeFriendship(userId,targetId);}
    public void decide(UUID userId,UUID requestId,String decision){if(!decision.equals("accept")&&!decision.equals("reject"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid decision");int changed=decision.equals("accept")?repository.accept(requestId,userId):repository.reject(requestId,userId);if(changed==0)throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Friend request not found");}
    public List<SocialModels.BlockedPerson> blocked(UUID userId){return repository.blocked(userId);}
    @Transactional public void block(UUID userId,UUID targetId){if(userId.equals(targetId))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"You cannot block yourself");repository.addBlock(userId,targetId);repository.removeFriendship(userId,targetId);repository.markMessagesRead(targetId,userId);}
    public void unblock(UUID userId,UUID targetId){repository.removeBlock(userId,targetId);}
    @Transactional public List<SocialModels.Message> messages(UUID userId,UUID friendId){requireFriends(userId,friendId);List<SocialModels.Message> result=new ArrayList<>(repository.messages(userId,friendId));repository.markMessagesRead(friendId,userId);Collections.reverse(result);return result;}
    public SocialModels.Message send(CurrentUser user,UUID friendId,SocialModels.SendMessage input){requireFriends(user.id(),friendId);var message=new SocialModels.Message(UUID.randomUUID(),user.id(),friendId,input.body().trim(),null,null,null,Instant.now());repository.insertMessage(message);push(friendId,user,message.body());return message;}
    public SocialModels.Message sendAttachment(CurrentUser user,UUID friendId,MultipartFile file,String requestedKind){
        requireFriends(user.id(),friendId);String kind=requestedKind.trim().toUpperCase();if(!kind.equals("IMAGE")&&!kind.equals("VIDEO"))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Attachment kind must be IMAGE or VIDEO");long limit=kind.equals("IMAGE")?MAX_IMAGE_BYTES:MAX_VIDEO_BYTES;if(file.isEmpty()||file.getSize()>limit)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,kind.equals("IMAGE")?"Images must be up to 8 MB":"Videos must be up to 25 MB");String original=safeOriginalName(file.getOriginalFilename());String extension=extensionFor(kind,original,file.getContentType());
        try{byte[] bytes=file.getBytes();if(!validSignature(kind,extension,bytes))throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"Unsupported or invalid attachment file");Files.createDirectories(messageDirectory);String fileName=UUID.randomUUID()+extension;Path target=messageDirectory.resolve(fileName).normalize();if(!target.getParent().equals(messageDirectory))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid filename");Files.write(target,bytes);var message=new SocialModels.Message(UUID.randomUUID(),user.id(),friendId,"",kind,"/api/social/attachments/"+fileName,original,Instant.now());repository.insertMessage(message);push(friendId,user,kind.equals("IMAGE")?"Sent a photo":"Sent a video");return message;}catch(IOException e){throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"Could not store attachment",e);}
    }
    public SocialModels.StoredFile attachment(String fileName){if(!fileName.matches("[0-9a-fA-F-]+\\.(jpg|jpeg|png|webp|gif|mp4|webm|mov|3gp)"))throw new ResponseStatusException(HttpStatus.NOT_FOUND);Path file=messageDirectory.resolve(fileName).normalize();if(!file.getParent().equals(messageDirectory)||!Files.isRegularFile(file))throw new ResponseStatusException(HttpStatus.NOT_FOUND);try{String type=Files.probeContentType(file);return new SocialModels.StoredFile(file,type==null?"application/octet-stream":type);}catch(IOException e){throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"Could not read attachment",e);}}
    private void requireFriends(UUID a,UUID b){if(!repository.areFriends(a,b))throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Direct messages are available to friends only");}
    private void push(UUID target,CurrentUser sender,String body){repository.subject(target).filter(v->!v.isBlank()).ifPresent(subject->events.convertAndSendToUser(subject,"/queue/notifications",new SocialModels.PushEvent("DIRECT_MESSAGE",sender.id(),sender.displayName(),body,null)));}
    private String safeOriginalName(String input){String name=input==null?"attachment":Path.of(input).getFileName().toString().replaceAll("[^A-Za-z0-9._ -]","_");return name.substring(0,Math.min(name.length(),255));}
    private String extensionFor(String kind,String name,String contentType){String lower=name.toLowerCase();List<String> allowed=kind.equals("IMAGE")?List.of(".jpg",".jpeg",".png",".webp",".gif"):List.of(".mp4",".webm",".mov",".3gp");for(String extension:allowed)if(lower.endsWith(extension))return extension;String type=contentType==null?"":contentType.toLowerCase();return switch(type){case "image/jpeg"->".jpg";case "image/png"->".png";case "image/webp"->".webp";case "image/gif"->".gif";case "video/mp4"->".mp4";case "video/webm"->".webm";case "video/quicktime"->".mov";case "video/3gpp"->".3gp";default->throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"Use JPG, PNG, WebP, GIF, MP4, WebM, MOV, or 3GP");};}
    private boolean validSignature(String kind,String extension,byte[] b){if(kind.equals("IMAGE")){if(extension.equals(".jpg")||extension.equals(".jpeg"))return b.length>=3&&(b[0]&255)==0xff&&(b[1]&255)==0xd8&&(b[2]&255)==0xff;if(extension.equals(".png"))return b.length>=8&&(b[0]&255)==0x89&&b[1]==0x50&&b[2]==0x4e&&b[3]==0x47;if(extension.equals(".gif"))return b.length>=6&&b[0]=='G'&&b[1]=='I'&&b[2]=='F';if(extension.equals(".webp"))return b.length>=12&&b[0]=='R'&&b[1]=='I'&&b[2]=='F'&&b[3]=='F'&&b[8]=='W'&&b[9]=='E'&&b[10]=='B'&&b[11]=='P';}else{if(extension.equals(".webm"))return b.length>=4&&(b[0]&255)==0x1a&&(b[1]&255)==0x45&&(b[2]&255)==0xdf&&(b[3]&255)==0xa3;return b.length>=12&&b[4]=='f'&&b[5]=='t'&&b[6]=='y'&&b[7]=='p';}return false;}
}
