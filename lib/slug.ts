import { customAlphabet } from 'nanoid';

/**
 * URL에 노출되는 8자 슬러그.
 *
 * 혼동하기 쉬운 문자(0/O, 1/l/I)를 뺐다. 공유 링크를 사람이 불러 주거나 손으로 옮겨
 * 적는 경우가 실제로 생긴다.
 */
const ALPHABET = '23456789abcdefghijkmnpqrstuvwxyz';

export const createSlug = customAlphabet(ALPHABET, 8);
