import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getMapDocument } from '@/lib/map/getMapDocument';
import { Viewer } from './Viewer';

type Props = { params: Promise<{ slug: string }> };

/**
 * 공유 링크의 대부분은 카카오톡 인앱 브라우저에서 열리고, 그 전에 카톡이 OG 메타를
 * 긁어 미리보기를 만든다. 뷰어를 SSR로 두는 이유가 이것이다.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const document = await getMapDocument(slug);
  if (!document) return { title: '지도를 찾을 수 없습니다 · MAP-LINE' };

  const title = document.title || '제목 없는 지도';
  const places = document.places.map((place) => place.name).filter(Boolean);
  const description =
    places.length > 0
      ? `${places.slice(0, 3).join(' → ')}${places.length > 3 ? ` 외 ${places.length - 3}곳` : ''}`
      : '손으로 그린 지도를 확인해 보세요.';

  return {
    title: `${title} · MAP-LINE`,
    description,
    openGraph: { title, description, type: 'article' },
    // og:image는 T14(정적 지도 썸네일 + Storage 캐시)에서 채운다.
  };
}

export default async function ViewerPage({ params }: Props) {
  const { slug } = await params;
  const document = await getMapDocument(slug);
  if (!document) notFound();

  return <Viewer document={document} />;
}
