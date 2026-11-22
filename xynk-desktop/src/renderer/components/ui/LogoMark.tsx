import iconUrl from '../../../../resources/xynk-icon.png?url';

interface LogoMarkProps {
  size?: number;
  className?: string;
}

export function LogoMark({size = 48, className}: LogoMarkProps) {
  return <img src={iconUrl} alt="XYNK" width={size} height={size} className={className} />;
}
