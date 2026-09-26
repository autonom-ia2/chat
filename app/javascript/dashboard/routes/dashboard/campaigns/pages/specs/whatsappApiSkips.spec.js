import { describe, expect, it } from 'vitest';

import { whatsappApiSkipLines } from '../whatsappApiSkips';

const t = (key, params) => `${key}:${params.count}`;

describe('whatsappApiSkipLines', () => {
  it('mostra quem recusou e quem foi descartado na Prospecção, cada um com a contagem', () => {
    expect(
      whatsappApiSkipLines({ opted_out_count: 2, discarded_count: 3 }, t)
    ).toEqual([
      'CAMPAIGN.WHATSAPP_API.TABLE.OPTED_OUT:2',
      'CAMPAIGN.WHATSAPP_API.TABLE.DISCARDED:3',
    ]);
  });

  it('não mostra motivo sem ninguém', () => {
    expect(
      whatsappApiSkipLines({ opted_out_count: 0, discarded_count: 1 }, t)
    ).toEqual(['CAMPAIGN.WHATSAPP_API.TABLE.DISCARDED:1']);
    expect(whatsappApiSkipLines({}, t)).toEqual([]);
  });
});
