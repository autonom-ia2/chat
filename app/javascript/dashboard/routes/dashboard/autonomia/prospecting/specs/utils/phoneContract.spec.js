// Tabela única de telefone (#677): o mesmo JSON roda no rspec
// (spec/services/autonomia/prospecting/phone_contract_spec.rb e as três pontas
// do backend), para o front e o backend darem o mesmo resultado.
import cases from '../../../../../../../../../spec/fixtures/prospecting_phone_contract_cases.json';
import {
  DEFAULT_PHONE_REGION,
  parsePhone,
  phoneE164,
  phoneRegionFromSettings,
} from '../../utils/phoneContract';
import {
  leadPhoneUrl,
  leadWhatsAppUrl,
  normalizedLeadPhone,
} from '../../utils/leadPhone';

describe('phoneContract · tabela compartilhada com o backend', () => {
  it('a tabela não está vazia', () => {
    expect(cases.length).toBeGreaterThan(10);
  });

  it.each(cases)('$caso: "$raw" ($region) vira $e164', item => {
    expect(phoneE164(item.raw, item.region)).toBe(item.e164 || '');
  });

  it.each(cases)(
    'card e listas: "$raw" ($region) monta tel e wa.me iguais',
    item => {
      const lead = { phone: item.raw };
      const digits = item.e164 ? item.e164.slice(1) : '';

      expect(normalizedLeadPhone(lead, item.region)).toBe(item.e164 || '');
      expect(leadPhoneUrl(lead, item.region)).toBe(
        item.e164 ? `tel:${item.e164}` : ''
      );
      expect(leadWhatsAppUrl(lead, item.region)).toBe(
        digits ? `https://wa.me/${digits}` : ''
      );
    }
  );
});

describe('phoneContract · detalhes', () => {
  it('parsePhone devolve E.164, dígitos e país', () => {
    expect(parsePhone('(55) 99988-7766', 'BR')).toEqual({
      e164: '+5555999887766',
      digits: '5555999887766',
      country: 'BR',
    });
    expect(parsePhone('1234', 'BR')).toBeNull();
    expect(parsePhone(null, 'BR')).toBeNull();
  });

  it('a região vem de search_country das configurações, com BR como padrão', () => {
    expect(DEFAULT_PHONE_REGION).toBe('BR');
    expect(phoneRegionFromSettings({ search_country: 'pt' })).toBe('PT');
    expect(phoneRegionFromSettings({ search_country: 'XX' })).toBe('BR');
    expect(phoneRegionFromSettings({})).toBe('BR');
    expect(phoneRegionFromSettings(null)).toBe('BR');
  });
});
