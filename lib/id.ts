/**
 * 클라이언트가 만드는 식별자. **항상 UUID 형식이어야 한다.**
 *
 * 서버가 이 값을 그대로 기본키로 쓰기 때문이다(`save_map_document`). 형식이 어긋나면
 * 저장이 통째로 실패한다.
 *
 * `crypto.randomUUID`는 보안 컨텍스트에서만 존재한다. localhost는 해당되지만 실기기
 * 테스트에 쓰는 `http://192.168.x.x:3000`은 아니라서, 그대로 쓰면 거기서만 터진다.
 * 그래서 아래로 내려가는 대체 경로를 두되 어느 경로든 UUID v4 형식을 지킨다.
 */
export function createId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return uuidV4From(randomBytes(16));
}

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);

  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    crypto.getRandomValues(bytes);
    return bytes;
  }
  // 최후의 수단. 지도 안에서만 유효한 로컬 식별자라 암호학적 강도는 필요하지 않다.
  for (let i = 0; i < length; i++) bytes[i] = Math.floor(Math.random() * 256);
  return bytes;
}

/** 16바이트를 UUID v4 표기로 만든다. */
function uuidV4From(bytes: Uint8Array): string {
  // 버전(4)과 variant 비트를 규격대로 박는다.
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;

  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 서버로 보내기 전 확인용. 오래된 로컬 초안에는 UUID가 아닌 옛 형식 id가 남아 있을 수 있다.
 */
export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}
