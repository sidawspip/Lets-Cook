import { Injectable, inject } from '@angular/core';
import { Client, IMessage, StompSubscription } from '@stomp/stompjs';
import { AuthService } from './auth.service';
import { WatchState } from './api.service';

export type WatchCommandType = 'LOAD'|'PLAY'|'PAUSE'|'SEEK'|'RATE'|'STOP'|'NEXT';
export interface WatchEvent { state: WatchState; commandId?: string; initiatedBy?: string; }

@Injectable({providedIn:'root'})
export class WatchSyncService {
  private readonly auth=inject(AuthService);
  private client?:Client;
  private subscription?:StompSubscription;
  private roomId='';
  private listener?: (event:WatchEvent)=>void;

  async connect(roomId:string,listener:(event:WatchEvent)=>void):Promise<void>{
    this.listener=listener;
    if(this.client?.active&&this.roomId===roomId)return;
    this.disconnect();this.roomId=roomId;
    const token=await this.auth.token();
    const host=location.protocol==='https:'?location.host:`${location.hostname}:8080`;
    const brokerURL=`${location.protocol==='https:'?'wss':'ws'}://${host}/ws`;
    this.client=new Client({brokerURL,connectHeaders:{Authorization:`Bearer ${token}`},reconnectDelay:2000,heartbeatIncoming:10000,heartbeatOutgoing:10000});
    this.client.onConnect=()=>{this.subscription=this.client?.subscribe(`/topic/rooms/${roomId}/watch`,message=>this.receive(message));};
    this.client.activate();
  }

  connected():boolean{return !!this.client?.connected;}

  publish(type:WatchCommandType,state:WatchState,values:{positionSeconds?:number;playbackRate?:number}={}):boolean{
    if(!this.client?.connected||!this.roomId)return false;
    this.client.publish({destination:`/app/rooms/${this.roomId}/watch/command`,body:JSON.stringify({commandId:crypto.randomUUID(),expectedRevision:state.revision??0,type,...values,clientTime:new Date().toISOString()})});
    return true;
  }

  disconnect():void{this.subscription?.unsubscribe();this.subscription=undefined;void this.client?.deactivate();this.client=undefined;this.roomId='';}
  private receive(message:IMessage):void{try{this.listener?.(JSON.parse(message.body) as WatchEvent);}catch{/* malformed events are ignored and REST reconciliation recovers */}}
}
