import { problemsOf, rowsOf } from '../importRows';

const ready = {
  status: 'ready',
  blocking: [],
  fixes: [],
  targets: { images: [], parts: [], fields: [] },
  report: {
    warnings: [
      {
        code: 'images_copied',
        key: 'EMAIL_IMPORT.REPORT.IMAGES_COPIED',
        severity: 'info',
        count: 4,
        items: [],
      },
      {
        code: 'tags_converted',
        key: 'EMAIL_IMPORT.REPORT.TAGS_CONVERTED',
        severity: 'info',
        count: 2,
        items: [
          { from: '{{lead.nome}}', to: '{{ nome }}' },
          { from: '{{lead.email}}', to: '{{ email }}' },
        ],
      },
      {
        code: 'footer_replaced',
        key: 'EMAIL_IMPORT.REPORT.FOOTER_REPLACED',
        severity: 'info',
        count: 1,
        items: [],
      },
      {
        code: 'quality_fixed',
        key: 'EMAIL_IMPORT.REPORT.QUALITY_FIXED',
        severity: 'info',
        count: 1,
        items: ['button_height'],
      },
      {
        code: 'tracking_removed',
        key: 'EMAIL_IMPORT.REPORT.TRACKING_REMOVED',
        severity: 'info',
        count: 1,
        items: [],
      },
      {
        code: 'unsafe_removed',
        key: 'EMAIL_IMPORT.REPORT.UNSAFE_REMOVED',
        severity: 'warning',
        count: 1,
        items: ['script'],
      },
      {
        code: 'layout_stacked',
        key: 'EMAIL_IMPORT.REPORT.LAYOUT_STACKED',
        severity: 'warning',
        count: 1,
        items: [],
      },
      {
        code: 'unknown_fields',
        key: 'EMAIL_IMPORT.REPORT.UNKNOWN_FIELDS',
        severity: 'blocking',
        count: 1,
        items: [],
      },
    ],
  },
};

describe('rowsOf', () => {
  it('says what the import did, in the order of the approved screen', () => {
    const rows = rowsOf(ready);

    expect(rows.map(row => [row.id, row.tone])).toEqual([
      ['images_copied', 'ok'],
      ['tags_converted', 'ok'],
      ['footer', 'ok'],
      ['quality-button_height', 'ok'],
      ['removed', 'info'],
      ['layout_stacked', 'info'],
    ]);
    expect(rows[0].text).toEqual({
      key: 'EMAIL_IMPORT.SCREEN.ROWS.IMAGES_COPIED',
      count: 4,
    });
    expect(rows[1].text.chips).toEqual({
      from: '{{lead.nome}}',
      to: '{{ nome }}',
    });
    expect(rows[1].hint).toEqual({
      key: 'EMAIL_IMPORT.SCREEN.ROWS.TAG_MORE',
      count: 1,
    });
    expect(rows[2].hint.key).toBe('EMAIL_IMPORT.SCREEN.ROWS.FOOTER_HINT');
    expect(rows[4].text.count).toBe(2);
    expect(rows[4].hint.list).toEqual([
      'EMAIL_IMPORT.SCREEN.ROWS.REMOVED_ITEMS.TRACKING_REMOVED',
      'EMAIL_IMPORT.SCREEN.ROWS.REMOVED_ITEMS.UNSAFE_REMOVED',
    ]);
  });

  it('puts each blocking problem first, with its own button, and the solved ones in green', () => {
    const data = {
      ...ready,
      blocking: [
        { code: 'image_missing' },
        { code: 'unresolved_parts' },
        { code: 'unknown_fields' },
      ],
      targets: {
        images: [
          { index: 0, kind: 'image', alt: 'Grão Vale' },
          { index: 1, kind: 'background', alt: null },
        ],
        parts: [{ id: 'trecho-1', text: 'Chegou a safra' }],
        fields: ['cupom'],
      },
      fixes: [
        {
          code: 'unknown_fields',
          choice: 'text',
          target: 'lead',
          value: 'OUTUBRO10',
        },
      ],
    };

    const rows = rowsOf(data);
    expect(
      rows.slice(0, 4).map(row => [row.id, row.tone, row.action.label])
    ).toEqual([
      ['image-0', 'warn', 'EMAIL_IMPORT.SCREEN.ROWS.SWAP_IMAGE'],
      ['image-1', 'warn', 'EMAIL_IMPORT.SCREEN.ROWS.SWAP_IMAGE'],
      ['part-trecho-1', 'warn', 'EMAIL_IMPORT.SCREEN.ROWS.SOLVE_PART'],
      ['field-cupom', 'warn', 'EMAIL_IMPORT.SCREEN.ROWS.CHOOSE'],
    ]);
    expect(rows[0].hint).toEqual({
      key: 'EMAIL_IMPORT.SCREEN.ROWS.IMAGE_MISSING_ALT',
      params: { alt: 'Grão Vale' },
    });
    expect(rows[1].text.key).toBe(
      'EMAIL_IMPORT.SCREEN.ROWS.BACKGROUND_MISSING'
    );
    expect(rows[3].text.chips).toEqual({ field: '{{ cupom }}' });
    expect(rows[4]).toMatchObject({
      id: 'fix-0',
      tone: 'ok',
      text: {
        key: 'EMAIL_IMPORT.SCREEN.ROWS.FIXED.FIELD_TEXT',
        chips: { field: '{{ lead }}' },
        params: { text: 'OUTUBRO10' },
      },
    });
  });

  it('names a field the way the person wrote it in the original', () => {
    const data = {
      ...ready,
      blocking: [{ code: 'unknown_fields' }],
      targets: { images: [], parts: [], fields: ['cupom'] },
      report: {
        warnings: [
          {
            code: 'unknown_fields',
            severity: 'blocking',
            count: 1,
            items: [{ from: '{{lead.cupom}}', key: 'cupom' }],
          },
        ],
      },
      fixes: [{ code: 'unknown_fields', choice: 'remove', target: 'cupom' }],
    };

    const [problem] = problemsOf(data);
    expect(problem.label).toBe('{{lead.cupom}}');
    const rows = rowsOf(data);
    expect(rows[0].text.chips).toEqual({ field: '{{lead.cupom}}' });
    expect(rows[1].text.chips).toEqual({ field: '{{lead.cupom}}' });
  });

  it('counts the other warnings so their sentences say one or many', () => {
    const rows = rowsOf({
      ...ready,
      report: {
        warnings: [
          {
            code: 'link_removed',
            key: 'EMAIL_IMPORT.REPORT.LINK_REMOVED',
            severity: 'warning',
            count: 3,
            items: [],
          },
        ],
      },
    });
    expect(rows.find(row => row.id === 'link_removed').text).toEqual({
      key: 'EMAIL_IMPORT.REPORT.LINK_REMOVED',
      count: 3,
    });
  });

  it('says which image was swapped, a background, or one without a name', () => {
    const rowsFor = fix =>
      rowsOf({ ...ready, fixes: [fix] }).find(row => row.id === 'fix-0').text;
    const upload = { code: 'image_missing', choice: 'upload' };

    expect(rowsFor({ ...upload, kind: 'image', target: 'Grão Vale' })).toEqual({
      key: 'EMAIL_IMPORT.SCREEN.ROWS.FIXED.IMAGE_UPLOAD',
      params: { target: 'Grão Vale' },
    });
    expect(rowsFor({ ...upload, kind: 'image' }).key).toBe(
      'EMAIL_IMPORT.SCREEN.ROWS.FIXED.IMAGE_UPLOAD_PLAIN'
    );
    expect(rowsFor({ ...upload, kind: 'background' }).key).toBe(
      'EMAIL_IMPORT.SCREEN.ROWS.FIXED.IMAGE_UPLOAD_BACKGROUND'
    );
  });

  it('offers to bring again when something blocks that the screen cannot fix', () => {
    const problems = problemsOf({ ...ready, blocking: [{ code: 'invalid' }] });
    expect(problems).toEqual([{ id: 'invalid', type: 'invalid' }]);
    expect(
      problemsOf({ ...ready, blocking: [{ code: 'image_missing' }] }).at(-1)
        .type
    ).toBe('invalid');
  });
});
