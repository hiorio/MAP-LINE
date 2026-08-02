import { afterEach, describe, expect, it, vi } from 'vitest';
import { createId, isUuid } from './id';

const original = globalThis.crypto;

afterEach(() => {
  vi.unstubAllGlobals();
  Object.defineProperty(globalThis, 'crypto', { value: original, configurable: true });
});

/** 보안 컨텍스트가 아닌 환경(실기기 LAN 주소)을 흉내 낸다. */
function stubCrypto(value: unknown) {
  Object.defineProperty(globalThis, 'crypto', { value, configurable: true });
}

describe('createId', () => {
  it('UUID 형식을 만든다', () => {
    expect(isUuid(createId())).toBe(true);
  });

  it('randomUUID가 없어도 UUID 형식을 지킨다', () => {
    // http://192.168.x.x:3000 은 보안 컨텍스트가 아니라 randomUUID가 없다.
    // 서버가 이 값을 기본키로 쓰므로 형식이 깨지면 저장이 통째로 실패한다.
    stubCrypto({ getRandomValues: original.getRandomValues.bind(original) });
    expect(isUuid(createId())).toBe(true);
  });

  it('crypto 자체가 없어도 UUID 형식을 지킨다', () => {
    stubCrypto(undefined);
    expect(isUuid(createId())).toBe(true);
  });

  it('대체 경로도 버전·variant 비트를 규격대로 박는다', () => {
    stubCrypto({ getRandomValues: (bytes: Uint8Array) => bytes.fill(0) });
    const id = createId();

    expect(id[14]).toBe('4'); // 버전 4
    expect(['8', '9', 'a', 'b']).toContain(id[19]); // variant
  });

  it('서로 다른 값을 만든다', () => {
    const ids = new Set(Array.from({ length: 500 }, () => createId()));
    expect(ids.size).toBe(500);
  });
});

describe('isUuid', () => {
  it('UUID를 통과시킨다', () => {
    expect(isUuid('b5bf17c4-4228-40cd-b283-c5a9bcd7ad55')).toBe(true);
  });

  it('옛 형식과 잘못된 값을 거른다', () => {
    // 예전 createId가 만들던 32자 hex와 timestamp 조합
    expect(isUuid('acb5e6900445621ff5dd4f6b8a870983')).toBe(false);
    expect(isUuid('m8x2p1-a9f3k2c1')).toBe(false);
    expect(isUuid('')).toBe(false);
    expect(isUuid(null)).toBe(false);
    expect(isUuid(123)).toBe(false);
  });
});
