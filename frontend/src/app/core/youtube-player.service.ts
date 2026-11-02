import { Injectable } from '@angular/core';

type PlayerEvent = { data:number; target:YoutubePlayer };
export interface YoutubePlayer {
  loadVideoById(id:string,start?:number):void; cueVideoById(id:string,start?:number):void;
  playVideo():void; pauseVideo():void; seekTo(seconds:number,allow:boolean):void;
  mute():void; unMute():void; isMuted():boolean; getVolume():number; setVolume(volume:number):void;
  getCurrentTime():number; getDuration():number; getPlayerState():number; getPlaybackRate():number;
  setPlaybackRate(rate:number):void; destroy():void;
  getAvailableQualityLevels?():string[]; setPlaybackQuality?(quality:string):void;
  loadModule?(module:string):void; unloadModule?(module:string):void;
  getOption?(module:string,option:string):unknown; setOption?(module:string,option:string,value:unknown):void;
}

@Injectable({providedIn:'root'})
export class YoutubePlayerService {
  private loader?:Promise<void>;
  load():Promise<void> {
    if((window as any).YT?.Player) return Promise.resolve();
    if(this.loader) return this.loader;
    this.loader=new Promise(resolve=>{
      const previous=(window as any).onYouTubeIframeAPIReady;
      (window as any).onYouTubeIframeAPIReady=()=>{ previous?.(); resolve(); };
      if(!document.querySelector('script[src="https://www.youtube.com/iframe_api"]')) {
        const script=document.createElement('script');script.src='https://www.youtube.com/iframe_api';document.head.appendChild(script);
      }
    }); return this.loader;
  }
  async create(element:HTMLElement,videoId:string,onState:(state:number)=>void,autoplay=false):Promise<YoutubePlayer> {
    await this.load(); element.replaceChildren();
    return new Promise(resolve=>{
      const player:YoutubePlayer=new (window as any).YT.Player(element,{videoId,width:'100%',height:'100%',
        playerVars:{autoplay:autoplay?1:0,mute:0,controls:0,disablekb:1,fs:0,iv_load_policy:3,playsinline:1,origin:location.origin,rel:0},
        events:{onReady:()=>{if(autoplay){player.unMute();player.playVideo();}resolve(player);},onStateChange:(event:PlayerEvent)=>onState(event.data)}});
    });
  }
}
