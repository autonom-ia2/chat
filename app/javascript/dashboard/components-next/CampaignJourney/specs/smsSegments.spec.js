import { smsStats } from '../smsSegments';
import { audienceChannelBadges } from '../audienceRows';
import { audienceChannels, channelAvailability } from '../audienceChannels';
import { renderTokens } from '../audienceTokens';

// #993 front of #1004 (api-1004.md §4.2 and §5a).
describe('smsStats — same rules as CampaignJourney::SmsSegments', () => {
  it('GSM-7: 160 in one part, then parts of 153; extension characters take 2', () => {
    expect(smsStats('')).toMatchObject({ segments: 0, units: 0 });
    expect(smsStats('a'.repeat(160))).toMatchObject({
      encoding: 'GSM-7',
      segments: 1,
      per_segment: 160,
    });
    expect(smsStats('a'.repeat(161))).toMatchObject({
      segments: 2,
      per_segment: 153,
    });
    expect(smsStats('€')).toMatchObject({ units: 2, characters: 1 });
  });

  it('a Portuguese accent switches to UCS-2 (70 / 67); an emoji takes 2 units', () => {
    expect(smsStats('ação')).toMatchObject({
      encoding: 'UCS-2',
      per_segment: 70,
    });
    expect(smsStats('á'.repeat(71))).toMatchObject({
      segments: 2,
      per_segment: 67,
    });
    expect(smsStats('😀')).toMatchObject({ characters: 1, units: 2 });
  });

  it('never splits a 2-unit character between parts', () => {
    // 154 units fit one 160-unit part; above 160, parts of 153 never split the 2-unit "€".
    expect(smsStats(`${'a'.repeat(152)}€`).segments).toBe(1);
    expect(smsStats(`${'a'.repeat(152)}€${'a'.repeat(10)}`).segments).toBe(2);
  });
});

describe('SMS badge of the audience (§5a)', () => {
  it('old audience without channels.sms: off with the WhatsApp count, no badge', () => {
    const channels = { whatsapp: { enabled: true, count: 98 } };
    expect(audienceChannelBadges(channels).map(badge => badge.channel)).toEqual(
      ['whatsapp']
    );
    expect(audienceChannels({ channels }).sms).toEqual({
      enabled: false,
      count: 98,
    });
    expect(channelAvailability('sms', audienceChannels({ channels }))).toEqual({
      available: false,
      reason: 'NO_SMS',
    });
  });

  it('SMS on shows "SMS · <count>" and makes the SMS card available', () => {
    const channels = {
      whatsapp: { enabled: true, count: 98 },
      sms: { enabled: true, count: 98 },
    };
    expect(audienceChannelBadges(channels)).toContainEqual({
      channel: 'sms',
      enabled: true,
      count: 98,
    });
    expect(
      channelAvailability('sms', audienceChannels({ channels })).available
    ).toBe(true);
  });
});

describe('renderTokens', () => {
  it('fills contact and audience fields with the first person, else a label', () => {
    const text =
      'Oi {{contact.first_name}}, vence {{publico.data_de_vencimento}}.';
    const sample = {
      name: 'Ana Souza',
      extra_values: { 'Data de Vencimento': '10/2026' },
    };
    expect(
      renderTokens(text, {
        sample,
        extraColumns: ['Data de Vencimento'],
        placeholder: token => `[${token}]`,
      })
    ).toBe('Oi Ana, vence 10/2026.');
    expect(
      renderTokens(text, {
        extraColumns: ['Data de Vencimento'],
        placeholder: () => '?',
      })
    ).toBe('Oi ?, vence ?.');
  });
});
