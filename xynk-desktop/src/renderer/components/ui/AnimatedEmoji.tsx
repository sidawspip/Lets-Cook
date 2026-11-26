import {animatedEmojiUrls,splitEmojiText} from '../../lib/animatedEmoji';
import { useEffect, useState } from 'react';
import heart from '../../assets/animated-emoji/heart.webp';
import fire from '../../assets/animated-emoji/fire.webp';
import laugh from '../../assets/animated-emoji/laugh.webp';
import love from '../../assets/animated-emoji/love.webp';
import clap from '../../assets/animated-emoji/clap.webp';
import surprise from '../../assets/animated-emoji/surprise.webp';
import cry from '../../assets/animated-emoji/cry.webp';
import thumbs from '../../assets/animated-emoji/thumbs.webp';

const artwork: Record<string, string> = {
  '❤': heart, '🔥': fire, '😂': laugh, '😍': love,
  '👏': clap, '😮': surprise, '😢': cry, '👍': thumbs,
};
const normalize = (emoji: string) => emoji.replace(/\uFE0F/g, '');

export function isEmojiOnly(value: string): boolean {
 const parts=splitEmojiText(value.trim()).filter(p=>p.text.trim());
 return parts.length>0 && parts.length<=3 && parts.every(p=>p.emoji);
}

function useReducedMotion() {
  const [reduced, setReduced] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    const update = () => setReduced(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);
  return reduced;
}

// Local quick reactions first, then catalog artwork loaded only as needed.
function EmojiArtwork({emoji,large=false}:{emoji:string;large?:boolean}) {
 const reduced=useReducedMotion();
 const [failed,setFailed]=useState<string[]>([]);
 const local=artwork[normalize(emoji)];
 const sources=[...(local?[local]:[]),...animatedEmojiUrls(emoji)];
 const url=sources.find(source=>!failed.includes(source));
 return <span className={`frame-emoji${large?' frame-emoji--large':''}`} role="img" aria-label={emoji}>
 {url&&!reduced?<img src={url} alt="" aria-hidden="true" className="frame-emoji-art" loading="lazy" referrerPolicy="no-referrer" draggable={false} onError={()=>setFailed(previous=>[...previous,url])}/>:<span aria-hidden="true" className={!reduced?'frame-emoji-fallback':undefined}>{emoji}</span>}
 </span>;
}
export function AnimatedEmoji({emoji,large=false}:{emoji:string;large?:boolean}) {
 return <>{splitEmojiText(emoji).map((part,index)=>part.emoji?<EmojiArtwork key={index+':'+part.text} emoji={part.text} large={large}/>:part.text)}</>;
}
export function EmojiText({text}:{text:string}) {
 return <AnimatedEmoji emoji={text}/>;
}
