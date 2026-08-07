/**
 * 외부 데이터 제공자의 저장 조건에 맞춰 서버에 남길 문서만 만든다.
 *
 * 카카오모빌리티 자동차 길찾기 결과는 자체 DB에 저장하지 않는다. 사용자가 고른
 * `mode: car`는 도화지의 데이터이므로 보존하되, 도로 좌표·거리·시간 캐시는 제거한다.
 * 입력 객체를 바꾸지 않아 편집 중 화면의 실시간 경로는 그대로 유지된다.
 */
export function stripNonPersistableRouteCaches<T extends object>(document: T): T {
  const record = document as Record<string, unknown>;
  const legs = record['legs'];
  if (!Array.isArray(legs)) return document;

  return {
    ...record,
    legs: legs.map((value) => {
      if (!isRecord(value) || value['mode'] !== 'car') return value;
      const leg = { ...value };
      delete leg['route'];
      return leg;
    }),
  } as T;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
