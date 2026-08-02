/**
 * `crypto.randomUUID`는 보안 컨텍스트에서만 존재한다. localhost는 해당되지만
 * 실기기 테스트에 쓰는 `http://192.168.x.x:3000`은 아니라서 그대로 쓰면 거기서만 터진다.
 * 로컬 식별자일 뿐 암호학적 강도가 필요하지 않으므로 대체 경로를 둔다.
 */
export function createId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}
