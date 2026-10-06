import {
  audienceColumnTokens,
  insertToken,
  normalizeKey,
} from '../audienceTokens';
import {
  buildEmailPayload,
  buildPreviewPayload,
  buildWhatsappApiPayload,
} from '../journeyChannelPayloads';

// #993 front of #999: the same keys CampaignImports::HeaderMapper.normalize_key gives.
describe('audienceTokens', () => {
  it('normalizes headers like the server, without regular expressions', () => {
    expect(normalizeKey('Data de Vencimento')).toBe('data_de_vencimento');
    expect(normalizeKey('  Ação - Prêmio ')).toBe('acao_premio');
  });

  it('gives a repeated key the "_2" suffix and skips empty ones', () => {
    expect(
      audienceColumnTokens(['Plano', 'plano', '***']).map(item => item.token)
    ).toEqual(['publico.plano', 'publico.plano_2']);
  });

  it('inserts a token at the cursor', () => {
    expect(insertToken('Oi !', 'contact.first_name', 3)).toBe(
      'Oi {{contact.first_name}}!'
    );
  });
});

describe('journey channel payloads (api-999.md §2)', () => {
  const draft = {
    channel: 'whatsapp_api',
    title: ' Renovação ',
    inboxId: 9,
    messageBody: 'Oi {{contact.company}}',
    apiTemplateId: null,
    defaults: { 'contact.company': 'sua empresa', 'publico.plano': 'x' },
    emailSender: 'inbox:12',
    fromName: '',
    fromEmail: '',
    replyInboxId: null,
  };

  it('WhatsApp API keeps defaults of the fields the message uses', () => {
    expect(
      buildWhatsappApiPayload({ audienceId: 5, draft, scheduledAt: null })
    ).toEqual({
      campaign_import_id: 5,
      channel: 'whatsapp_api',
      campaign: {
        title: 'Renovação',
        inbox_id: 9,
        scheduled_at: null,
        message_body: 'Oi {{contact.company}}',
        variable_defaults: { 'contact.company': 'sua empresa' },
      },
    });
  });

  it('e-mail by direct inbox and the preview body per channel', () => {
    expect(buildEmailPayload({ audienceId: 5, draft }).campaign).toEqual({
      title: 'Renovação',
      delivery_mode: 'direct_inbox',
      sender_inbox_id: 12,
    });
    expect(
      buildPreviewPayload({
        audienceId: 5,
        draft: { ...draft, channel: 'email' },
      })
    ).toEqual({ campaign_import_id: 5, channel: 'email' });
  });
});
