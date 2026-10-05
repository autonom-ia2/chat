// SMS parts of a text (#993 front of #1004), the same rules as CampaignJourney::SmsSegments on the
// server (docs/campaigns/publicos/api-1004.md §4.2), with plain character lookups:
// GSM-7 (basic table, extension characters take 2 units; 160 / 153 per part) or UCS-2 (UTF-16
// units, emoji = 2; 70 / 67 per part). A 2-unit character is never split between parts.
const GSM_BASIC = new Set(
  '@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
);
const GSM_EXTENSION = new Set('\f^{}\\[~]|€');
const LIMITS = {
  'GSM-7': { single: 160, multi: 153 },
  'UCS-2': { single: 70, multi: 67 },
};
const BASIC_PLANE_MAX = 0xffff;

const isGsm = char => GSM_BASIC.has(char) || GSM_EXTENSION.has(char);

const unitsOf = (char, encoding) => {
  if (encoding === 'GSM-7') return GSM_EXTENSION.has(char) ? 2 : 1;
  return char.codePointAt(0) > BASIC_PLANE_MAX ? 2 : 1;
};

const segmentsFor = (sizes, total, limit) => {
  if (total === 0) return 0;
  if (total <= limit.single) return 1;
  let segments = 1;
  let used = 0;
  sizes.forEach(size => {
    if (used + size > limit.multi) {
      segments += 1;
      used = 0;
    }
    used += size;
  });
  return segments;
};

/** => { encoding, characters, units, segments, per_segment } like the API's message_stats. */
export const smsStats = text => {
  const chars = Array.from(String(text || ''));
  const encoding = chars.every(isGsm) ? 'GSM-7' : 'UCS-2';
  const sizes = chars.map(char => unitsOf(char, encoding));
  const limit = LIMITS[encoding];
  const units = sizes.reduce((sum, size) => sum + size, 0);
  return {
    encoding,
    characters: chars.length,
    units,
    segments: segmentsFor(sizes, units, limit),
    per_segment: units > limit.single ? limit.multi : limit.single,
  };
};
