import { PELES, peleDaCaixa } from '../pele';
import { diaDaMensagem, horaDaMensagem, rotuloDoDia } from '../dataDaConversa';

describe('peleDaCaixa (#1702)', () => {
  it('WhatsApp oficial e WAHA ganham a pele com a chave ligada', () => {
    expect(peleDaCaixa({ channel_type: 'Channel::Whatsapp' }, true)).toBe(
      PELES.WHATSAPP
    );
    expect(
      peleDaCaixa({ channel_type: 'Channel::Api', waha_provider: true }, true)
    ).toBe(PELES.WHATSAPP);
  });

  it('sem a chave, API comum, Twilio ou e-mail: sem pele', () => {
    expect(
      peleDaCaixa({ channel_type: 'Channel::Whatsapp' }, false)
    ).toBeNull();
    expect(peleDaCaixa({ channel_type: 'Channel::Api' }, true)).toBeNull();
    expect(
      peleDaCaixa({ channel_type: 'Channel::TwilioSms' }, true)
    ).toBeNull();
    expect(peleDaCaixa({ channel_type: 'Channel::Email' }, true)).toBeNull();
    expect(peleDaCaixa(undefined, true)).toBeNull();
  });
});

describe('hora e dia no fuso da conta (#1702)', () => {
  // 16/10/2026 02:30 UTC = 15/10/2026 23:30 em São Paulo.
  const quando = Date.UTC(2026, 9, 16, 2, 30) / 1000;
  const t = chave =>
    ({
      'CONVERSA_CANAL.DIA.HOJE': 'Hoje',
      'CONVERSA_CANAL.DIA.ONTEM': 'Ontem',
    })[chave];

  it('a hora sai no fuso da conta, não no do computador', () => {
    expect(horaDaMensagem(quando, 'America/Sao_Paulo')).toBe('23:30');
    expect(horaDaMensagem(quando, 'UTC')).toBe('02:30');
  });

  it('o dia muda pelo fuso da conta', () => {
    expect(diaDaMensagem(quando, 'America/Sao_Paulo')).toBe('2026-10-15');
    expect(diaDaMensagem(quando, 'UTC')).toBe('2026-10-16');
  });

  it('Hoje, Ontem, dia da semana e data', () => {
    const fuso = 'America/Sao_Paulo';
    const agora = Date.UTC(2026, 9, 16, 15, 0) / 1000;
    expect(rotuloDoDia({ quando: agora, agora, fuso, t })).toBe('Hoje');
    expect(rotuloDoDia({ quando, agora, fuso, t })).toBe('Ontem');
    const tresDias = Date.UTC(2026, 9, 13, 15, 0) / 1000;
    expect(rotuloDoDia({ quando: tresDias, agora, fuso, t })).toBe(
      'Terça-feira'
    );
    const antigo = Date.UTC(2026, 8, 1, 15, 0) / 1000;
    expect(rotuloDoDia({ quando: antigo, agora, fuso, t })).toBe(
      '1 de setembro de 2026'
    );
  });
});
