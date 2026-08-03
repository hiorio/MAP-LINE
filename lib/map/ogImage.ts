import 'server-only';
import {
  clampLevel,
  fetchStaticMap,
  OG_HEIGHT,
  OG_SCALE,
  OG_WIDTH,
} from '@/lib/kakao/staticMap';
import { renderOgOverlay } from '@/lib/render/ogOverlay';
import { getServiceClient } from '@/lib/supabase/server';
import { createStaticProjection } from './staticProjection';
import type { StoredMapDocument } from './getMapDocument';

/**
 * OG 썸네일을 가져온다. 없거나 낡았으면 만들어서 Storage에 캐시한다.
 *
 * 설계안 §9.1: 정적 지도는 일 1,000건 무료다. 매 조회마다 호출하면 인기 지도 하나가
 * 하루치를 다 먹는다. 그래서 (1) 실제로 썸네일이 요청됐을 때만 만들고,
 * (2) 지도 내용이 바뀐 뒤에만 다시 만든다.
 */
const BUCKET = 'og';

export async function getOrCreateOgImage(document: StoredMapDocument): Promise<Blob | null> {
  const supabase = getServiceClient();
  if (!supabase) return null;

  const cached = await readCache(document);
  if (cached) return cached;

  let png: Buffer;
  try {
    const level = clampLevel(document.zoomLevel);
    const base = await fetchStaticMap({ center: document.center, level });
    png = await composeOverlay(base, document, level);
  } catch (cause) {
    console.error('[ogImage] 정적 지도 생성 실패', cause);
    return null;
  }

  const blob = new Blob([new Uint8Array(png)], { type: 'image/png' });
  await writeCache(document.slug, blob);
  return blob;
}

/**
 * 받아 온 지도 위에 핀·화살표·손그림·메모를 얹는다.
 *
 * 합성이 실패해도 썸네일 자체는 나와야 한다. 표시 없는 지도라도 없는 것보다는 낫다.
 */
async function composeOverlay(
  base: ArrayBuffer,
  document: StoredMapDocument,
  level: number,
): Promise<Buffer> {
  const map = Buffer.from(base);

  const svg = renderOgOverlay({
    stops: document.stops,
    legs: document.legs ?? [],
    strokes: document.strokes,
    labels: document.labels,
    showCandidateLinks: document.showCandidateLinks,
    showStopArrows: document.showStopArrows,
    level,
    width: OG_WIDTH,
    height: OG_HEIGHT,
    scale: OG_SCALE,
    project: createStaticProjection({
      center: document.center,
      level,
      width: OG_WIDTH,
      height: OG_HEIGHT,
    }),
  });

  try {
    // sharp는 Next가 이미 쓰고 있지만, 여기서만 필요하므로 요청 시점에 들인다.
    const { default: sharp } = await import('sharp');
    return await sharp(map)
      .composite([{ input: Buffer.from(svg), top: 0, left: 0 }])
      .png()
      .toBuffer();
  } catch (cause) {
    console.error('[ogImage] 오버레이 합성 실패, 지도만 내보낸다', cause);
    return map;
  }
}

async function readCache(document: StoredMapDocument): Promise<Blob | null> {
  const supabase = getServiceClient();
  if (!supabase || !document.ogImageUrl || !document.ogUpdatedAt) return null;

  // 내용이 바뀐 뒤라면 캐시를 버린다.
  if (new Date(document.ogUpdatedAt) < new Date(document.updatedAt)) return null;

  const { data, error } = await supabase.storage.from(BUCKET).download(objectPath(document.slug));
  if (error || !data) return null;
  return data;
}

async function writeCache(slug: string, blob: Blob): Promise<void> {
  const supabase = getServiceClient();
  if (!supabase) return;

  // 버킷이 없으면 만든다. 사용자가 대시보드에서 손댈 필요가 없게 한다.
  // 카카오톡 크롤러가 읽어야 하므로 public이어야 한다.
  const { error: bucketError } = await supabase.storage.createBucket(BUCKET, {
    public: true,
    fileSizeLimit: 5 * 1024 * 1024,
    allowedMimeTypes: ['image/png'],
  });
  // 이미 있으면 그대로 진행한다.
  if (bucketError && !/exist/i.test(bucketError.message)) {
    console.error('[ogImage] 버킷 생성 실패', bucketError);
    return;
  }

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(objectPath(slug), blob, { contentType: 'image/png', upsert: true });

  if (uploadError) {
    console.error('[ogImage] 업로드 실패', uploadError);
    return;
  }

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(objectPath(slug));
  const { error: rpcError } = await supabase.rpc('set_map_og_image', {
    p_slug: slug,
    p_url: data.publicUrl,
  });
  if (rpcError) console.error('[ogImage] URL 기록 실패', rpcError);
}

function objectPath(slug: string): string {
  return `${slug}.png`;
}
