import Image from 'next/image';
import Link from 'next/link';
import appIcon from '@/ios/MapLine/Assets.xcassets/AppIcon.appiconset/icon-1024.png';

interface BrandHomeLinkProps {
  className?: string;
  iconSize?: number;
  nameClassName?: string;
  priority?: boolean;
  subtitle?: string;
}

/** iOS 앱과 웹이 같은 서비스임을 보여 주는 공통 브랜드 표식. */
export function BrandHomeLink({
  className = '',
  iconSize = 30,
  nameClassName = 'text-sm font-semibold',
  priority = false,
  subtitle,
}: BrandHomeLinkProps) {
  return (
    <Link
      href="/"
      aria-label="도화지 홈"
      className={`inline-flex min-w-0 items-center gap-2.5 ${className}`}
    >
      <Image
        src={appIcon}
        alt=""
        aria-hidden="true"
        width={iconSize}
        height={iconSize}
        priority={priority}
        className="shrink-0 rounded-[22%] border border-ink/10 shadow-sm"
      />
      <span className="min-w-0">
        <span className={`block leading-tight text-ink ${nameClassName}`}>도화지</span>
        {subtitle && (
          <span className="mt-1 block truncate text-xs font-medium text-ink/45">{subtitle}</span>
        )}
      </span>
    </Link>
  );
}
