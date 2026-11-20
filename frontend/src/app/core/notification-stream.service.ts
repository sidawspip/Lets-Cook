import { Injectable, inject } from '@angular/core';
import { Client, IMessage, StompSubscription } from '@stomp/stompjs';
import { AuthService } from './auth.service';

export interface PushEvent { type:'ROOM_INVITE'|'DIRECT_MESSAGE'|'SCREEN_SHARE_REQUEST'|'SCREEN_SHARE_APPROVED'|'SCREEN_SHARE_REVOKED'|'HOST_MUTE'|'HOST_UNMUTE_REQUEST';senderId:string;senderName:string;body:string;roomId?:string; }

@Injectable({providedIn:'root'})
export class NotificationStreamService {
  private readonly auth=inject(AuthService);private client?:Client;private subscription?:StompSubscription;
  async connect(listener:(event:PushEvent)=>void):Promise<void>{
    if(this.client?.active)return;const token=await this.auth.token();const host=location.protocol==='https:'?location.host:`${location.hostname}:8080`;
    this.client=new Client({brokerURL:`${location.protocol==='https:'?'wss':'ws'}://${host}/ws`,connectHeaders:{Authorization:`Bearer ${token}`},reconnectDelay:2000,heartbeatIncoming:10000,heartbeatOutgoing:10000});
    this.client.onConnect=()=>{this.subscription=this.client?.subscribe('/user/queue/notifications',(message:IMessage)=>{try{listener(JSON.parse(message.body) as PushEvent);}catch{}});};this.client.activate();
  }
  disconnect():void{this.subscription?.unsubscribe();this.subscription=undefined;void this.client?.deactivate();this.client=undefined;}
}
