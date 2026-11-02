package com.letscook.platform.room;

import com.letscook.platform.common.CurrentUser;
import java.util.List;
import java.util.UUID;

/**
 * Room-domain use cases for lifecycle, discovery, membership, governance, invites, and media access.
 * Controllers must use this contract instead of calling room persistence directly.
 */
public interface RoomService {
    /** Lists active rooms owned by or joined by the user. */
    List<RoomDtos.RoomSummary> listFor(CurrentUser user);
    /** Creates a unique room and returns its summary plus one-time key when applicable. */
    RoomDtos.RoomCreated create(CurrentUser owner,RoomDtos.CreateRoomRequest request);
    /** Deletes a room after verifying ownership. */
    void delete(CurrentUser actor,UUID roomId);
    /** Lists pending join requests for a host/co-host. */
    List<RoomDtos.JoinRequest> joinRequests(CurrentUser actor,UUID roomId);
    /** Approves or rejects a pending join request as a room manager. */
    void decideJoinRequest(CurrentUser actor,UUID roomId,UUID userId,boolean approve);
    /** Lists active members and permissions for a room manager. */
    List<RoomDtos.RoomMember> members(CurrentUser actor,UUID roomId);
    /** Changes a non-host member's screen-sharing grant as owner. */
    void setScreenPermission(CurrentUser actor,UUID roomId,UUID userId,boolean allowed);
    /** Removes and bans a non-owner member. */
    void kickMember(CurrentUser actor,UUID roomId,UUID userId);
    /** Directly invites a user after membership, block, and invite-preference checks. */
    void inviteUser(CurrentUser actor,UUID roomId,UUID userId);
    /** Transfers ownership, promotes a co-host, or demotes a co-host. */
    void setLeadership(CurrentUser actor,UUID roomId,UUID userId,String action);
    /** Discovers live rooms visible to the user. */
    List<RoomDtos.PublicRoom> publicLive(CurrentUser user);
    /** Partially updates owner-controlled room settings. */
    void updateSettings(CurrentUser actor,UUID roomId,RoomDtos.UpdateRoomSettings input);
    /** Evaluates direct room entry through visibility, policy, key, capacity, and approval rules. */
    RoomDtos.AccessResult unlock(CurrentUser user,UUID roomId,String accessKey);
    /** Creates a role-limited share-code invite as host/co-host. */
    RoomDtos.InviteCreated createInvite(CurrentUser actor,UUID roomId,RoomDtos.CreateInviteRequest request);
    /** Consumes a valid share-code invite and returns resulting membership state. */
    RoomDtos.AccessResult acceptInvite(CurrentUser user,String code,String accessKey);
    /** Issues a role-aware LiveKit token for an active member. */
    RoomDtos.MediaToken createMediaToken(CurrentUser user,UUID roomId);
}
