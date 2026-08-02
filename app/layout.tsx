import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
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
