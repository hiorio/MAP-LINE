import type { Metadata, Viewport } from 'next';
import appIcon from '@/ios/MapLine/Assets.xcassets/AppIcon.appiconset/icon-1024.png';
import './globals.css';

/**
 * 지도를 두 손가락으로 벌리면 지도가 아니라 페이지 전체가 확대되는 일이 있었다.
 * 브라우저의 기본 핀치 줌이 지도의 줌과 겹쳐 일어나는 일이고, 한 번 페이지가
 * 확대되면 컨텍스트 메뉴가 화면 밖으로 밀려 손이 닿지 않는다.
 *
 * 확대할 대상이 지도뿐인 화면이라 페이지 줌은 끄는 편이 맞다. 글자 크기를 키워
 * 읽으려는 사람에게는 손해이지만, 이 화면의 내용은 지도이고 지도는 자체 줌이 있다.
 */
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: '#FAF8F4',
};

/**
 * og:image는 절대 URL이어야 크롤러가 읽는다. 상대 경로를 절대 경로로 바꾸는 기준점이
 * metadataBase다. 운영 도메인이 정해지면 NEXT_PUBLIC_SITE_URL을 채운다.
 */
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  applicationName: '도화지',
  title: {
    default: '도화지',
    template: '%s | 도화지',
  },
  description: '핀, 메모, 손그림과 실제 이동 경로를 한 장의 지도로 만들고 공유합니다.',
  icons: {
    icon: [{ url: appIcon.src, type: 'image/png', sizes: '1024x1024' }],
    apple: [{ url: appIcon.src, type: 'image/png', sizes: '1024x1024' }],
  },
  manifest: '/manifest.webmanifest',
  openGraph: {
    type: 'website',
    siteName: '도화지',
    title: '도화지',
    description: '핀, 메모, 손그림과 실제 이동 경로를 한 장의 지도로 만들고 공유합니다.',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body className="antialiased">{children}</body>
    </html>
  );
}
