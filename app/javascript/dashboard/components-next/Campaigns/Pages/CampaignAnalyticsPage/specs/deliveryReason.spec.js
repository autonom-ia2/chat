import { deliveryReason, rawDeliveryReason } from '../deliveryReason';

const t = key => `t:${key}`;

describe('deliveryReason', () => {
  it('traduz o motivo de quem recusou mensagens ativas', () => {
    expect(deliveryReason({ error_message: 'opted_out' }, t)).toBe(
      't:CAMPAIGN.WHATSAPP.ANALYTICS.TABLE.REASON_OPTED_OUT'
    );
  });

  it('mantém o texto do provedor nos demais motivos', () => {
    expect(
      deliveryReason({ error_message: 'Template parameters are missing' }, t)
    ).toBe('Template parameters are missing');
    expect(deliveryReason({ error_title: 'Rate limit' }, t)).toBe('Rate limit');
    expect(deliveryReason({ error_code: 131049 }, t)).toBe(131049);
  });

  it('devolve vazio quando não há motivo', () => {
    expect(deliveryReason({}, t)).toBe('');
    expect(rawDeliveryReason({})).toBe('');
  });
});
