import { useEffect, useState } from 'react';

interface MediaPreviewProps {
  mediaId: string;
  provider: string;
  thumbnailUrl?: string;
  contentLabel: string;
  sensitive?: boolean;
  className?: string;
  isLoading?: boolean;
}

const PLACEHOLDER_GRADIENTS: Record<string, string> = {
  YOUTUBE: 'from-[#FF0000] to-[#CC0000]',
  VIMEO: 'from-[#1AB7EA] to-[#009DD9]',
  TWITCH: 'from-[#9146FF] to-[#6441A5]',
  CRUNCHYROLL: 'from-[#F47521] to-[#E03E3E]',
  NETFLIX: 'from-[#E50914] to-[#B8070F]',
  PRIME_VIDEO: 'from-[#00A8E1] to-[#0077B3]',
  DIRECT_MP4: 'from-[#4ADE80] to-[#22C55E]',
  DIRECT_HLS: 'from-[#F472B6] to-[#EC4899]',
  WEB: 'from-[#6366F1] to-[#8B5CF6]',
};

export function MediaPreview({
  mediaId,
  provider,
  thumbnailUrl,
  contentLabel,
  sensitive = false,
  className = '',
  isLoading = false,
}: MediaPreviewProps) {
  const [imgError, setImgError] = useState(false);
  const [imgLoaded, setImgLoaded] = useState(false);

  const getProviderGradient = (prov: string) => {
    const upper = prov.toUpperCase();
    return PLACEHOLDER_GRADIENTS[upper] || 'from-[#6366F1] to-[#8B5CF6]';
  };

  const shouldBlur = sensitive && !imgLoaded;

  const getThumbnailUrl = () => {
    if (thumbnailUrl) return thumbnailUrl;
    if (provider.toUpperCase() === 'YOUTUBE' && mediaId) {
      return `https://i.ytimg.com/vi/${mediaId}/hqdefault.jpg`;
    }
    return null;
  }

  const url = getThumbnailUrl();

  useEffect(() => {
    setImgError(false);
    setImgLoaded(false);
  }, [url]);

  return (
    <div
      className={`relative overflow-hidden bg-gradient-to-br ${getProviderGradient(provider)} ${className}`}
      role="img"
      aria-label={contentLabel}
    >
      {url && !imgError && (
        <img
          src={url}
          alt=""
          loading="lazy"
          className={`w-full h-full object-cover transition-opacity duration-300 ${
            imgLoaded ? 'opacity-100' : 'opacity-0'
          } ${shouldBlur ? 'blur-[20px]' : ''}`}
          onLoad={() => setImgLoaded(true)}
          onError={() => setImgError(true)}
        />
      )}

      {!url || imgError || isLoading ? (
        <div className="w-full h-full flex items-center justify-center bg-black/50">
          {isLoading ? (
            <svg className="w-8 h-8 text-white/60 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10" strokeLinecap="round" strokeDasharray="31.4 31.4" />
            </svg>
          ) : (
            <svg className="w-10 h-10 text-white/40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <rect x="2" y="2" width="20" height="20" rx="2" />
              <path d="M23 22l-7-7" />
              <circle cx="12" cy="8" r="2" />
              <path d="M9 18h12a2 2 0 0 0 0-4h-12" />
            </svg>
          )}
        </div>
      ) : null}

      {sensitive && !imgLoaded && (
        <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" />
      )}

      {sensitive && (
        <div className="absolute top-2 right-2 px-2 py-1 bg-red-500/80 backdrop-blur text-[10px] font-black text-white rounded">
          18+
        </div>
      )}

      {shouldBlur && (
        <div className="absolute inset-0 flex items-center justify-center text-white/70 text-xs font-medium px-4">
          Sensitive content hidden
        </div>
      )}
    </div>
  );
}
