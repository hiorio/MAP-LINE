import type { MetadataRoute } from 'next';
import appIcon from '@/ios/MapLine/Assets.xcassets/AppIcon.appiconset/icon-1024.png';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: '도화지 — 함께 만드는 모임 동선 지도',
    short_name: '도화지',
    description: '핀, 메모, 손그림과 실제 이동 경로를 한 장의 지도로 만들고 공유합니다.',
    start_url: '/',
    display: 'standalone',
    background_color: '#FAF8F4',
    theme_color: '#FAF8F4',
    icons: [
      {
        src: appIcon.src,
        sizes: '1024x1024',
        type: 'image/png',
      },
    ],
  };
}
