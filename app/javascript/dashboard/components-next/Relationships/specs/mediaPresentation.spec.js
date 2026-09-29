import {
  formatMediaDate,
  formatMediaSize,
  mediaContactGroups,
  mediaTypeKey,
} from '../mediaPresentation';

it.each([
  [{ content_type: 'application/pdf', file_type: 'file' }, 'PDF'],
  [{ content_type: 'image/png', file_type: 'image' }, 'image'],
  [{ content_type: 'audio/ogg', file_type: 'audio' }, 'audio'],
  [{ content_type: 'video/mp4', file_type: 'video' }, 'video'],
  [{ content_type: 'application/zip', file_type: 'file' }, 'file'],
])('presents a friendly type for %j', (row, expected) => {
  expect(mediaTypeKey(row)).toBe(expected);
});

it.each([
  [0, '0 KB'],
  [1, '0.001 KB'],
  [512, '0.5 KB'],
  [1024, '1 KB'],
  [1536, '1.5 KB'],
  [1024 ** 2, '1 MB'],
  [1024 ** 3, '1 GB'],
])('formats %i bytes without exposing raw byte counts', (bytes, expected) => {
  expect(formatMediaSize(bytes, 'en')).toBe(expected);
});

it('uses the chosen locale for sizes and browser local dates rather than assuming a Brazilian zone', () => {
  expect(formatMediaSize(1536, 'pt_BR')).toBe('1,5 KB');
  const timestamp = '2026-09-29T01:30:00Z';
  expect(formatMediaDate(timestamp, 'pt_BR')).toBe(
    new Intl.DateTimeFormat('pt-BR', {
      dateStyle: 'short',
      timeStyle: 'short',
    }).format(new Date(timestamp))
  );
  // The focused test command fixes the browser environment to UTC.
  expect(formatMediaDate(timestamp, 'en-GB')).toBe('29/09/2026, 01:30');
});

it('marks contact boundaries without changing server order or deduplicating same-name occurrences', () => {
  const rows = [
    { id: 1, filename: 'report.pdf', contact: { id: 4, name: 'Same name' } },
    { id: 2, filename: 'report.pdf', contact: { id: 4, name: 'Same name' } },
    { id: 3, filename: 'report.pdf', contact: { id: 5, name: 'Same name' } },
  ];
  const groups = mediaContactGroups(rows, true);
  expect(groups.map(group => group.contact.id)).toEqual([4, 5]);
  expect(groups.flatMap(group => group.rows)).toEqual(rows);
  expect(mediaContactGroups(rows, false)).toHaveLength(1);
  expect(mediaContactGroups([], true)).toEqual([]);
  expect(mediaContactGroups(rows.slice(1), true)[0].contact.id).toBe(4);
});
