import type { Metadata } from 'next';
import './globals.css';

/**
 * og:image는 절대 URL이어야 크롤러가 읽는다. 상대 경로를 절대 경로로 바꾸는 기준점이
 * metadataBase다. 운영 도메인이 정해지면 NEXT_PUBLIC_SITE_URL을 채운다.
 */
const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: 'MAP-LINE',
  description: '손으로 그린 지도를 링크 하나로 공유합니다.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body className="antialiased">{children}</body>
    </html>
  );
}
