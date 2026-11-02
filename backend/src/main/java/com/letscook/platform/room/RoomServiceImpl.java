package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import org.springframework.stereotype.Service;
import java.util.List;
import java.util.UUID;

/**
 * Application boundary for room business operations.
 *
 * <p>Exposes one stable service contract to the room and invite APIs while keeping all room
 * persistence and transactional membership invariants behind {@link RoomRepository}.</p>
 */
@Service
class RoomServiceImpl implements RoomService {
    private final RoomRepository repository;
    RoomServiceImpl(RoomRepository repository){this.repository=repository;}
    public List<RoomDtos.RoomSummary> listFor(CurrentUser user){return repository.listFor(user);}
    public RoomDtos.RoomCreated create(CurrentUser owner,RoomDtos.CreateRoomRequest request){return repository.create(owner,request);}
    public void delete(CurrentUser actor,UUID roomId){repository.delete(actor,roomId);}
    public List<RoomDtos.JoinRequest> joinRequests(CurrentUser actor,UUID roomId){return repository.joinRequests(actor,roomId);}
    public void decideJoinRequest(CurrentUser actor,UUID roomId,UUID userId,boolean approve){repository.decideJoinRequest(actor,roomId,userId,approve);}
    public List<RoomDtos.RoomMember> members(CurrentUser actor,UUID roomId){return repository.members(actor,roomId);}
    public void setScreenPermission(CurrentUser actor,UUID roomId,UUID userId,boolean allowed){repository.setScreenPermission(actor,roomId,userId,allowed);}
    public void kickMember(CurrentUser actor,UUID roomId,UUID userId){repository.kickMember(actor,roomId,userId);}
    public void inviteUser(CurrentUser actor,UUID roomId,UUID userId){repository.inviteUser(actor,roomId,userId);}
    public void setLeadership(CurrentUser actor,UUID roomId,UUID userId,String action){repository.setLeadership(actor,roomId,userId,action);}
    public List<RoomDtos.PublicRoom> publicLive(CurrentUser user){return repository.publicLive(user);}
    public void updateSettings(CurrentUser actor,UUID roomId,RoomDtos.UpdateRoomSettings input){repository.updateSettings(actor,roomId,input);}
    public RoomDtos.AccessResult unlock(CurrentUser user,UUID roomId,String accessKey){return repository.unlock(user,roomId,accessKey);}
    public RoomDtos.InviteCreated createInvite(CurrentUser actor,UUID roomId,RoomDtos.CreateInviteRequest request){return repository.createInvite(actor,roomId,request);}
    public RoomDtos.AccessResult acceptInvite(CurrentUser user,String code,String accessKey){return repository.acceptInvite(user,code,accessKey);}
    public RoomDtos.MediaToken createMediaToken(CurrentUser user,UUID roomId){return repository.createMediaToken(user,roomId);}
}
