import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

/**
 * `.env.local`을 설정 단계에서 읽어 테스트 워커에 명시적으로 넘긴다.
 *
 * `@next/env`를 쓰지 않는 이유: CommonJS 모듈이라 이 ESM 설정 파일에서 명명 import가
 * 조용히 실패한다(에러 없이 값만 안 들어온다). 형식이 단순하니 직접 읽는다.
 *
 * 값이 없으면 빈 문자열이 들어가고, 통합 테스트는 스스로 스킵된다. 새로 받은 개발
 * 환경이나 CI에서 테스트가 빨갛게 뜨는 것보다 조용히 넘어가는 편이 낫다.
 */
function readEnvFile(path: string): Record<string, string> {
  if (!existsSync(path)) return {};

  const parsed: Record<string, string> = {};
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const separator = trimmed.indexOf('=');
    if (separator === -1) continue;

    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (value.length >= 2 && /^(".*"|'.*')$/s.test(value)) value = value.slice(1, -1);
    parsed[key] = value;
  }
  return parsed;
}

const fileEnv = readEnvFile(fileURLToPath(new URL('./.env.local', import.meta.url)));

const passthrough = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'KAKAO_REST_KEY',
] as const;

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('.', import.meta.url)),
      // 번들러가 없는 테스트 환경에서는 표식 패키지를 빈 모듈로 바꾼다.
      'server-only': fileURLToPath(new URL('./test/stubs/server-only.ts', import.meta.url)),
    },
  },
  test: {
    environment: 'node',
    include: ['{lib,store,app}/**/*.test.ts'],
    // 실제 환경변수가 있으면 그것을 우선한다(CI에서 주입하는 경우).
    env: Object.fromEntries(
      passthrough.map((key) => [key, process.env[key] ?? fileEnv[key] ?? '']),
    ),
    // 통합 테스트가 같은 Supabase 프로젝트를 건드리므로 파일 간 병렬 실행을 끈다.
    fileParallelism: false,
  },
});
