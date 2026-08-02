import { describe, expect, it } from 'vitest';
import { extractDistrict, parseShareText } from './parseShareText';

describe('parseShareText', () => {
  it('네이버 지도 공유 텍스트에서 이름·주소·지역을 뽑는다', () => {
    const result = parseShareText(
      ['[네이버 지도] 스타벅스 강남대로점', '서울특별시 강남구 강남대로 390', 'https://naver.me/xxxxx'].join('\n'),
    );

    expect(result).toEqual({
      name: '스타벅스 강남대로점',
      address: '서울특별시 강남구 강남대로 390',
      region: '강남구',
      query: '스타벅스 강남대로점 강남구',
    });
  });

  it('카카오맵 공유 텍스트를 처리한다', () => {
    const result = parseShareText(
      ['스타벅스 강남대로점', '서울 강남구 강남대로 390', 'http://kko.kr/abcd', '카카오맵에서 보기'].join('\n'),
    );

    expect(result?.name).toBe('스타벅스 강남대로점');
    expect(result?.region).toBe('강남구');
  });

  it('URL이 본문 중간에 섞여 있어도 제거한다', () => {
    const result = parseShareText('망원동 티라미수 https://naver.me/abc 여기 맛있음');
    expect(result?.name).toBe('망원동 티라미수 여기 맛있음');
  });

  it('장소명만 있으면 주소와 지역 없이 이름만 돌려준다', () => {
    const result = parseShareText('연남동 감나무집\nhttps://kko.kr/zzz');
    expect(result).toEqual({ name: '연남동 감나무집', query: '연남동 감나무집' });
  });

  it('이름에 이미 지역이 들어 있으면 질의에 중복해서 붙이지 않는다', () => {
    const result = parseShareText('강남구청역 3번 출구\n서울특별시 강남구 학동로 지하 426');
    expect(result?.query).toBe('강남구청역 3번 출구');
  });

  it('주소만 붙여넣으면 주소를 이름으로 쓴다', () => {
    const result = parseShareText('경기도 성남시 분당구 판교역로 235');
    expect(result?.name).toBe('경기도 성남시 분당구 판교역로 235');
    // 시/도(경기도)를 걷어낸 뒤 첫 시·군·구 토큰
    expect(result?.region).toBe('성남시');
  });

  it('URL만 있으면 null을 반환한다', () => {
    expect(parseShareText('https://naver.me/xxxxx')).toBeNull();
    expect(parseShareText('   ')).toBeNull();
    expect(parseShareText('')).toBeNull();
  });

  it('여러 형태의 접두 브래킷을 제거한다', () => {
    expect(parseShareText('[카카오맵] 광화문광장')?.name).toBe('광화문광장');
    expect(parseShareText('(네이버 지도) 광화문광장')?.name).toBe('광화문광장');
    expect(parseShareText('【네이버 지도】 광화문광장')?.name).toBe('광화문광장');
  });

  it('안내 문구 줄은 버린다', () => {
    const result = parseShareText('경복궁\n길찾기\n위치 보기');
    expect(result?.name).toBe('경복궁');
  });
});

describe('extractDistrict', () => {
  it('시/도 접두의 "시"를 구·군으로 오인하지 않는다', () => {
    expect(extractDistrict('서울특별시 강남구 강남대로 390')).toBe('강남구');
    expect(extractDistrict('부산광역시 해운대구 우동')).toBe('해운대구');
    expect(extractDistrict('세종특별자치시 한누리대로')).toBeUndefined();
  });

  it('도 아래의 시와 구를 순서대로 만나면 앞의 것을 쓴다', () => {
    expect(extractDistrict('경기도 성남시 분당구 판교역로 235')).toBe('성남시');
  });

  it('군 단위도 인식한다', () => {
    expect(extractDistrict('강원특별자치도 양양군 현북면')).toBe('양양군');
  });
});
