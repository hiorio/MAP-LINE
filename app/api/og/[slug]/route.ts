import { NextResponse } from 'next/server';
import { getMapDocument } from '@/lib/map/getMapDocument';
import { getOrCreateOgImage } from '@/lib/map/ogImage';

/**
 * OG 썸네일을 이미지 바이트로 직접 돌려준다.
 *
 * Storage 공개 URL로 302 리다이렉트하는 편이 싸지만, 크롤러 중에는 og:image의
 * 리다이렉트를 따라가지 않는 것이 있다. 공유 링크 대부분이 카카오톡에서 열리는
 * 제품이라 미리보기가 안 뜨는 위험을 지느니 우리가 한 번 더 전달한다.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const document = await getMapDocument(slug);
  if (!document) {
    return NextResponse.json({ error: '지도를 찾을 수 없습니다.' }, { status: 404 });
  }

  const image = await getOrCreateOgImage(document);
  if (!image) {
    return NextResponse.json({ error: '썸네일을 만들지 못했습니다.' }, { status: 502 });
  }

  return new NextResponse(image, {
    headers: {
      'Content-Type': 'image/png',
      // 크롤러가 여러 번 긁어도 카카오를 다시 호출하지 않도록 캐시를 길게 준다.
      'Cache-Control': 'public, max-age=3600, s-maxage=86400',
    },
  });
}
