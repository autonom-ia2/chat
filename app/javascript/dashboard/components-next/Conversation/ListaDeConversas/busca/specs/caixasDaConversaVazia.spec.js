import {
  caixaJaEscolhida,
  caixasParaEmail,
  caixasParaTelefone,
  linhaDaCaixa,
  pedidoDeConversaVazia,
  semInstagram,
  telefonePossivel,
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

  it('telefone novo: só as caixas que mandam para número (API só a do WAHA), WhatsApp e o do celular primeiro (#2255)', () => {
    const caixas = caixasParaTelefone(
      [
        { id: 1, name: 'B', channel_type: 'Channel::Api', waha_provider: true },
        { id: 6, name: 'Webhook', channel_type: 'Channel::Api' },
        { id: 2, name: 'E-mail', channel_type: 'Channel::Email' },
        { id: 3, name: 'A', channel_type: 'Channel::Whatsapp' },
        { id: 4, name: 'Insta', channel_type: 'Channel::Instagram' },
        { id: 5, name: 'SMS', channel_type: 'Channel::Sms' },
      ],
      ['1', '2', '3', '4', '5', '6']
    );
    expect(caixas.map(caixa => caixa.id)).toEqual([3, 1, 5]);
    expect(caixas[0].channelType).toBe('Channel::Whatsapp');
  });

  // inbox_view de função personalizada traz caixas de que a pessoa não é membro: o create da
  // conversa responderia 403 depois de gravar o contato.
  it('telefone e e-mail novos: a caixa fora da lista do servidor não é oferecida', () => {
    const daConta = [
      { id: 1, name: 'Minha', channel_type: 'Channel::Whatsapp' },
      { id: 2, name: 'Alheia', channel_type: 'Channel::Whatsapp' },
      { id: 3, name: 'Meu e-mail', channel_type: 'Channel::Email' },
      { id: 4, name: 'E-mail alheio', channel_type: 'Channel::Email' },
    ];
    expect(
      caixasParaTelefone(daConta, ['1', '3']).map(caixa => caixa.id)
    ).toEqual([1]);
    expect(caixasParaEmail(daConta, ['1', '3']).map(caixa => caixa.id)).toEqual(
      [3]
    );
    expect(caixasParaTelefone(daConta)).toEqual([]);
    expect(caixasParaEmail(daConta, [])).toEqual([]);
  });

  it('telefone novo: a caixa que o servidor disse livre começa no texto livre; as outras, no modelo (#2257)', () => {
    const caixas = caixasParaTelefone(
      [
        { id: 1, name: 'A', channel_type: 'Channel::Whatsapp' },
        { id: 2, name: 'B', channel_type: 'Channel::Whatsapp' },
      ],
      ['1', '2'],
      ['2']
    );
    expect(
      Object.fromEntries(
        caixas.map(caixa => [caixa.id, caixa.whatsappApiStart])
      )
    ).toEqual({ 1: false, 2: true });
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
      email: '',
      caixasLivres: [],
      caixasPermitidas: [],
    });
    expect(pedidoDeConversaVazia({ telefone: '+5511955554444' })).toEqual({
      contatoId: '',
      telefone: '+5511955554444',
      email: '',
      caixasLivres: [],
      caixasPermitidas: [],
    });
    expect(
      pedidoDeConversaVazia({ telefone: '+5511955554444', caixas: '1,5' })
        .caixasPermitidas
    ).toEqual(['1', '5']);
    // ?caixas= só vale com telefone ou e-mail novo.
    expect(
      pedidoDeConversaVazia({ comecar: '3', caixas: '1' }).caixasPermitidas
    ).toEqual([]);
    expect(
      pedidoDeConversaVazia({ telefone: '+5511955554444', livre: '1,5' })
        .caixasLivres
    ).toEqual(['1', '5']);
    // ?livre= só vale com telefone novo.
    expect(
      pedidoDeConversaVazia({ comecar: '3', livre: '1' }).caixasLivres
    ).toEqual([]);
    expect(
      pedidoDeConversaVazia({ email: 'nova@exemplo.test', caixas: '2' })
    ).toEqual({
      contatoId: '',
      telefone: '',
      email: 'nova@exemplo.test',
      caixasLivres: [],
      caixasPermitidas: ['2'],
    });
    // ?comecar= repetido: vale o primeiro.
    expect(pedidoDeConversaVazia({ comecar: ['3', '4'] }).contatoId).toBe('3');
    expect(pedidoDeConversaVazia({ messageId: '9' })).toBeNull();
    expect(pedidoDeConversaVazia()).toBeNull();
  });
});

describe('e-mail e telefone novos (#2211)', () => {
  it('e-mail novo: só as caixas de e-mail', () => {
    expect(
      caixasParaEmail(
        [
          { id: 1, name: 'W', channel_type: 'Channel::Whatsapp' },
          { id: 2, name: 'E', channel_type: 'Channel::Email' },
          {
            id: 3,
            name: 'API',
            channel_type: 'Channel::Api',
            waha_provider: true,
          },
        ],
        ['1', '2', '3']
      ).map(caixa => caixa.id)
    ).toEqual([2]);
  });

  it.each([
    ['+5511955554444', true],
    ['+551140000001', true],
    ['+55119', false],
    ['', false],
    ['abc', false],
  ])('telefonePossivel(%s) = %s', (telefone, possivel) => {
    expect(telefonePossivel(telefone)).toBe(possivel);
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
