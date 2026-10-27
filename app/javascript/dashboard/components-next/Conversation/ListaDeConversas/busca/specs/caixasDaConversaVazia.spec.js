import {
  caixaJaEscolhida,
  caixasParaTelefone,
  linhaDaCaixa,
  pedidoDeConversaVazia,
  semInstagram,
  temInstagram,
} from '../caixasDaConversaVazia';

describe('caixasDaConversaVazia (#2211)', () => {
  it('tira o Instagram das caixas', () => {
    expect(
      semInstagram([
        { id: 1, channelType: 'Channel::Whatsapp' },
        { id: 2, channelType: 'Channel::Instagram' },
      ]).map(caixa => caixa.id)
    ).toEqual([1]);
  });

  it('telefone novo: só as caixas que mandam para número, WhatsApp primeiro', () => {
    const caixas = caixasParaTelefone([
      { id: 1, name: 'B', channel_type: 'Channel::Api' },
      { id: 2, name: 'E-mail', channel_type: 'Channel::Email' },
      { id: 3, name: 'A', channel_type: 'Channel::Whatsapp' },
      { id: 4, name: 'Insta', channel_type: 'Channel::Instagram' },
      { id: 5, name: 'SMS', channel_type: 'Channel::Sms' },
    ]);
    expect(caixas.map(caixa => caixa.id)).toEqual([3, 5, 1]);
    expect(caixas[0].channelType).toBe('Channel::Whatsapp');
  });

  it('uma caixa só já vem escolhida; mais de uma, não', () => {
    expect(caixaJaEscolhida([{ id: 7 }])).toBe(7);
    expect(caixaJaEscolhida([{ id: 7 }, { id: 8 }])).toBeNull();
    expect(caixaJaEscolhida([])).toBeNull();
  });

  it('diz se a conta tem Instagram', () => {
    expect(temInstagram([{ channel_type: 'Channel::Instagram' }])).toBe(true);
    expect(temInstagram([{ channel_type: 'Channel::Email' }])).toBe(false);
  });

  it('a rota pede a conversa vazia pelo contato ou pelo telefone novo', () => {
    expect(pedidoDeConversaVazia({ comecar: '3' })).toEqual({
      contatoId: '3',
      telefone: '',
    });
    expect(pedidoDeConversaVazia({ telefone: '+5511955554444' })).toEqual({
      contatoId: '',
      telefone: '+5511955554444',
    });
    expect(pedidoDeConversaVazia({ messageId: '9' })).toBeNull();
    expect(pedidoDeConversaVazia()).toBeNull();
  });
});

describe('linhaDaCaixa (#2211)', () => {
  it('mostra o e-mail ou o número como a lista escreve, sem o prefixo do Twilio', () => {
    expect(
      linhaDaCaixa({ channelType: 'Channel::Email', email: 'oi@loja.com' })
    ).toBe('oi@loja.com');
    expect(
      linhaDaCaixa({
        channelType: 'Channel::Whatsapp',
        phoneNumber: '+5511988887777',
      })
    ).toBe('+55 11 98888-7777');
    expect(
      linhaDaCaixa({
        channelType: 'Channel::TwilioSms',
        phoneNumber: 'whatsapp:+5511999990000',
      })
    ).toBe('+55 11 99999-0000');
    expect(linhaDaCaixa(null)).toBe('');
  });

  it('WhatsApp pelo celular (API do WAHA) mostra o número da sessão', () => {
    expect(
      linhaDaCaixa({
        channelType: 'Channel::Api',
        wahaProvider: true,
        wahaPhoneNumber: '+5511900003303',
      })
    ).toBe('+55 11 90000-3303');
    expect(linhaDaCaixa({ channelType: 'Channel::Api' })).toBe('');
  });
});
