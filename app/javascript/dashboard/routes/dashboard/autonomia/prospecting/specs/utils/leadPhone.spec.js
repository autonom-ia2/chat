import {
  BRAZIL_PHONE_REGION,
  leadPhoneUrl,
  leadWhatsAppUrl,
  normalizedLeadPhone,
} from '../../utils/leadPhone';

const PORTUGAL = { dialCode: '351', nationalLengths: [9] };

describe('leadPhone · normalização por região', () => {
  it('sem região usa o Brasil: DDI 55 para número nacional de 10 ou 11 dígitos', () => {
    expect(normalizedLeadPhone({ phone: '(41) 99999-0001' })).toBe(
      '+5541999990001'
    );
    expect(normalizedLeadPhone({ phone: '4133330002' })).toBe('+554133330002');
    expect(normalizedLeadPhone({ phone: '5541999990001' })).toBe(
      '+5541999990001'
    );
    expect(normalizedLeadPhone({ phone: '+1 415 555 0100' })).toBe(
      '+14155550100'
    );
    expect(normalizedLeadPhone({ phone: '' })).toBe('');
    expect(
      normalizedLeadPhone({ phone: '4133330002' }, BRAZIL_PHONE_REGION)
    ).toBe('+554133330002');
  });

  it('com a região da busca aplica o DDI dela ao número nacional', () => {
    expect(normalizedLeadPhone({ phone: '912 345 678' }, PORTUGAL)).toBe(
      '+351912345678'
    );
    expect(normalizedLeadPhone({ phone: '351912345678' }, PORTUGAL)).toBe(
      '+351912345678'
    );
  });

  it('prefere o número de WhatsApp ao telefone e monta os links', () => {
    const lead = { phone: '4133330002', whatsapp_phone: '41999990001' };
    expect(normalizedLeadPhone(lead)).toBe('+5541999990001');
    expect(leadPhoneUrl(lead)).toBe('tel:+5541999990001');
    expect(leadWhatsAppUrl(lead)).toBe('https://wa.me/5541999990001');
    expect(leadWhatsAppUrl({ ...lead, whatsapp_url: 'https://wa.me/x' })).toBe(
      'https://wa.me/x'
    );
  });
});
