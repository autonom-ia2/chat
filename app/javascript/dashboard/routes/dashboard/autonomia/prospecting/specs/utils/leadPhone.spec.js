import {
  leadPhoneUrl,
  leadWhatsAppUrl,
  normalizedLeadPhone,
} from '../../utils/leadPhone';

describe('leadPhone · normalização por região', () => {
  it('sem região usa o Brasil', () => {
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
  });

  it('lê o 55 sem +55 como DDD do Rio Grande do Sul', () => {
    expect(normalizedLeadPhone({ phone: '(55) 99988-7766' })).toBe(
      '+5555999887766'
    );
  });

  it('com a região da busca aplica o DDI dela ao número nacional', () => {
    expect(normalizedLeadPhone({ phone: '912 345 678' }, 'PT')).toBe(
      '+351912345678'
    );
    expect(normalizedLeadPhone({ phone: '351912345678' }, 'PT')).toBe(
      '+351912345678'
    );
  });

  it('número inválido não vira link', () => {
    expect(normalizedLeadPhone({ phone: '1234' })).toBe('');
    expect(leadPhoneUrl({ phone: '1234' })).toBe('');
    expect(leadWhatsAppUrl({ phone: '1234' })).toBe('');
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

  it('os links de ligar e de WhatsApp recebem a região da busca', () => {
    const lead = { phone: '912 345 678' };
    expect(leadPhoneUrl(lead, 'PT')).toBe('tel:+351912345678');
    expect(leadWhatsAppUrl(lead, 'PT')).toBe('https://wa.me/351912345678');
  });
});
