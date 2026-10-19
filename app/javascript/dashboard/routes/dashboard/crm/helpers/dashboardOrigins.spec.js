import { ORIGIN_SOURCES, originRows } from './dashboardOrigins';

const sale = (cents, currency = 'BRL') => [{ currency, value_cents: cents }];

describe('originRows (#1876)', () => {
  it('names every origin the server sends, campaigns and the website chat included', () => {
    const keys = ORIGIN_SOURCES.map(source => source.key);

    expect(keys).toEqual(
      expect.arrayContaining([
        'campaign_whatsapp',
        'campaign_email',
        'campaign_sms',
        'campaign_live_chat',
        'none',
      ])
    );
    expect(keys).not.toContain('unknown');
  });

  it('keeps a blank origin out of the ad row and puts "no origin" last', () => {
    const rows = originRows([
      { source: 'none', won_count: 5, won_value_by_currency: sale(9000) },
      { source: '', won_count: 2, won_value_by_currency: sale(100) },
      { source: 'campaign_live_chat', won_count: 1, won_value_by_currency: [] },
      { source: 'meta_ctwa', won_count: 3, won_value_by_currency: sale(300) },
    ]);

    expect(rows.map(row => [row.source, row.wonCount])).toEqual([
      ['meta_ctwa', 3],
      ['campaign_live_chat', 1],
      ['none', 7],
    ]);
    expect(rows[2].labelKey).toBe('CRM_DASHBOARD.ORIGIN.SOURCES.NONE');
  });

  it('adds up two server rows that land on the same line instead of keeping only the last one', () => {
    const rows = originRows([
      {
        source: 'future_source',
        won_count: 1,
        won_value_by_currency: sale(100),
      },
      { source: 'none', won_count: 2, won_value_by_currency: sale(200) },
    ]);

    expect(rows).toEqual([
      expect.objectContaining({
        source: 'none',
        wonCount: 3,
        valueList: [{ currency: 'BRL', value_cents: 300 }],
      }),
    ]);
  });
});
