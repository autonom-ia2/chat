// Splits a translated sentence into plain text and "chips" (a field like {{ cupom }} shown as code),
// so client data is never rendered as HTML. Each param is passed as a marker, then the sentence is
// cut on the marker character — string methods only.
const MARK = '\u0001';

export const chipSegments = (translate, key, chips = {}, params = {}) => {
  const names = Object.keys(chips);
  const markers = Object.fromEntries(
    names.map((name, index) => [name, `${MARK}${index}${MARK}`])
  );
  const text = translate(key, { ...params, ...markers });
  return text
    .split(MARK)
    .map((piece, index) => {
      if (index % 2 === 0) return { text: piece };
      const name = names[Number(piece)];
      return { text: chips[name], chip: true };
    })
    .filter(segment => segment.text !== '');
};
