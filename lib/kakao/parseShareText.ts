/**
 * 타 지도 앱의 공유 텍스트에서 **장소명과 주소만** 뽑아낸다. URL은 버린다.
 *
 * 단축 URL(naver.me, kko.kr)을 서버에서 풀어 좌표를 추출하는 방식은 기술적으로는
 * 쉽지만 타사 약관상 명백한 회색지대이고, 서비스가 커지면 차단된다. 대신 여기서 얻은
 * 이름·지역으로 Kakao Local API에 정식 재검색을 걸어 우리 좌표를 얻는다.
 *
 * 그 결과 (1) 정당하게 발급받은 카카오 데이터만 저장하고, (2) 타사 단축 URL 구조가
 * 바뀌어도 깨지지 않으며, (3) 사용자에게는 여전히 "붙여넣기 한 번"이다.
 */

export interface ParsedShare {
  /** 검색에 쓸 장소명 */
  name: string;
  /** 공유 텍스트에 포함돼 있던 주소 전문 */
  address?: string;
  /** 시/군/구. 동명 지점을 좁히는 데 쓴다 */
  region?: string;
  /** Kakao Local 키워드 검색에 그대로 넣을 질의 */
  query: string;
}

const URL_PATTERN = /https?:\/\/\S+|\b(?:www\.|naver\.me|kko\.kr|place\.map\.kakao\.com)\S*/gi;

/** 접두 브래킷: [네이버 지도], [카카오맵] 등 */
const LEADING_BRACKET = /^[[(【]\s*[^\])】]*\s*[\])】]\s*/;

const SIDO =
  '서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주';
const SIDO_SUFFIX = '특별자치시|특별자치도|특별시|광역시|도';
const ADDRESS_HEAD = new RegExp(`^(?:${SIDO})(?:${SIDO_SUFFIX})?\\s`);

/** 시/도 접두를 걷어낸 나머지에서 첫 번째 시·군·구 토큰 */
const DISTRICT = /([가-힣]+(?:시|군|구))(?:\s|$)/;

/** 공유 텍스트에 흔히 섞여 오는 홍보 문구 */
const NOISE = /^(?:카카오맵에서\s*보기|네이버\s*지도에서\s*보기|위치\s*보기|길찾기)$/;

export function parseShareText(raw: string): ParsedShare | null {
  return parseShareTexts(raw)[0] ?? null;
}

/** 한 번의 공유에 여러 장소가 들어오면 주소 줄을 경계로 각각 분리한다. */
export function parseShareTexts(raw: string): ParsedShare[] {
  const lines = raw
    .split(/[\r\n]+/)
    // URL을 지운 자리에 공백이 남으므로 줄 단위로 공백을 정규화한다.
    .map((line) => line.replace(URL_PATTERN, ' ').replace(/\s+/g, ' ').trim())
    .map((line) => line.replace(LEADING_BRACKET, '').trim())
    .filter((line) => line.length > 0 && !NOISE.test(line));

  if (lines.length === 0) return [];

  const addressIndices = lines
    .map((line, index) => (ADDRESS_HEAD.test(line) ? index : -1))
    .filter((index) => index >= 0);

  if (addressIndices.length === 0) {
    const name = lines[0];
    return name ? [{ name, query: name }] : [];
  }

  const parsed: ParsedShare[] = [];
  let previousAddressIndex = -1;
  for (const addressIndex of addressIndices) {
    const address = lines[addressIndex];
    if (!address) continue;

    // 지도 앱은 보통 `제목 → 장소명 → 주소` 순서로 중복해 보낸다. 주소에 가장 가까운
    // 앞줄이 실제 장소명일 가능성이 가장 높다. 주소만 온 경우에는 주소를 이름으로 쓴다.
    const precedingNames = lines
      .slice(previousAddressIndex + 1, addressIndex)
      .filter((line) => !ADDRESS_HEAD.test(line));
    const name = precedingNames.at(-1) ?? address;
    parsed.push(makeParsed(name, address));
    previousAddressIndex = addressIndex;
  }

  // 같은 항목이 텍스트와 attributed text 양쪽으로 온 경우 한 번만 남긴다.
  const seen = new Set<string>();
  return parsed.filter((item) => {
    const key = `${item.name}\u0000${item.address ?? ''}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function makeParsed(name: string, address: string): ParsedShare {
  const region = extractDistrict(address);
  return {
    name,
    address,
    ...(region ? { region } : {}),
    query: region && !name.includes(region) ? `${name} ${region}` : name,
  };
}

/**
 * "서울특별시 강남구 강남대로 390" → "강남구"
 * 시/도 접두를 먼저 걷어내야 "특별시"의 '시'를 구·군으로 오인하지 않는다.
 */
export function extractDistrict(address: string): string | undefined {
  const rest = address.replace(ADDRESS_HEAD, '').trim();
  return DISTRICT.exec(rest)?.[1];
}
