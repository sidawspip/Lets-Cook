import catalog from '../assets/animated-emoji/catalog.json';
const noto = new Set(catalog.noto);
const fluent = new Set(catalog.fluent);

export function animatedEmojiUrls(emoji: string): string[] {
  const points = Array.from(emoji, c => c.codePointAt(0)!.toString(16));
  const variants = [points, points.filter(p => p !== 'fe0f')];
  const urls: string[] = [];
  for (const variant of variants) {
    const google = variant.join('_');
    if (noto.has(google)) urls.push(`https://fonts.gstatic.com/s/e/notoemoji/latest/${google}/512.webp`);
    const microsoft = variant.join('-');
    if (fluent.has(microsoft)) urls.push(`https://raw.githubusercontent.com/bignutty/fluent-emoji/main/animated/${microsoft}.png`);
  }
  return [...new Set(urls)];
}

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const emojiPattern = /\p{Extended_Pictographic}|\p{Regional_Indicator}|\u20E3/u;
export const splitEmojiText = (text: string) => Array.from(segmenter.segment(text), part => ({text: part.segment, emoji: emojiPattern.test(part.segment)}));
