/* eslint-disable vue/one-component-per-file */
// Chaves que o WhatsApp Híbrido (#1709) grava nas mensagens da caixa WAHA e a pele
// desenha como o app. Cada item: com a pele e sem a pele (igual à main).
import { computed, defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { provideMessageContext } from '../../message/provider.js';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import AudioDoWhatsapp from '../audio/AudioDoWhatsapp.vue';
import { citacaoSolta } from '../citacaoSolta';
import { midiaIndisponivel, audioDeVoz } from '../marcasDaMensagem';
import { avisoDeTemporarias } from '../temporarias/temporarias';
import {
  contatosDoBalao,
  numeroParaConversar,
  variosContatos,
} from '../midia/contatos';
import { ehPedido, resumoDoPedido } from '../pedido/pedido';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
// Quem vê e edita contatos (#1849): os cartões mostram Conversar e Salvar.
vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({
    canViewRelationshipRecords: { value: true },
    canManageRelationshipRecords: { value: true },
  }),
}));

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const global = () => ({
  ...montagem,
  plugins: [...montagem.plugins, i18n()],
  stubs: { ...montagem.stubs, NovaConversaEntrada: true },
});

const comPele = (pele, filho) =>
  defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => filho();
    },
  });

const montar = (props = {}, { pele = PELES.WHATSAPP } = {}) =>
  mount(
    comPele(pele, () =>
      h(Message, {
        id: 1,
        messageType: MESSAGE_TYPES.INCOMING,
        status: MESSAGE_STATUS.SENT,
        content: 'Olá',
        conversationId: 7,
        createdAt: AGORA,
        currentUserId: 1,
        sender: { id: 7, name: 'Maria', type: 'Contact' },
        ...props,
      })
    ),
    { global: global() }
  );

const balao = (wrapper, nome) => wrapper.find(`[data-bubble-name="${nome}"]`);

describe('1. citação de mensagem fora da conversa (quoted_message)', () => {
  // O conector WAHA grava assim quando não acha a mensagem: só o aparelho do cliente
  // mandou o trecho, e o fromMe pode ter sido forjado.
  const naoAchada = {
    messageId: null,
    content: '',
    fromMe: true,
    hasMedia: true,
    unverified: true,
  };
  const deOutraConversa = {
    messageId: 90,
    conversationId: 12,
    // Escrito no app do cliente: *x* é negrito (#1740).
    content: 'Olha a *foto*',
    senderType: 'Contact',
    attachmentType: 'image',
  };

  it('não conferida com fromMe true: sem "You" nem nome, faixa cinza, aviso, "Media", sem toque', () => {
    const wrapper = montar({
      contentAttributes: { quotedMessage: naoAchada },
    });
    const citacao = wrapper.find('[data-citacao-solta]');
    expect(citacao.exists()).toBe(true);
    expect(citacao.text()).not.toContain('You');
    expect(citacao.text()).not.toContain('Maria');
    expect(citacao.text()).toContain('Media');
    expect(citacao.find('[data-citacao-nao-conferida]').text()).toBe(
      "Snippet sent by the customer's device, not verified"
    );
    expect(citacao.find('.i-ph-paperclip').exists()).toBe(true);
    expect(citacao.classes()).toContain('border-s-[#8696A0]');
    expect(citacao.classes()).not.toContain('border-s-[#1A6B42]');
    expect(citacao.classes()).not.toContain('border-s-[#5E44D8]');
    expect(citacao.classes()).not.toContain('cursor-pointer');
    expect(citacao.attributes('role')).toBeUndefined();
    expect(citacao.attributes('tabindex')).toBeUndefined();
    expect(wrapper.find('[data-citacao-de-outra-conversa]').exists()).toBe(
      false
    );
  });

  it('de outra conversa, do cliente: nome dele, faixa roxa, ícone da foto e o texto', () => {
    const wrapper = montar({
      contentAttributes: { quotedMessage: deOutraConversa },
    });
    const citacao = wrapper.find('[data-citacao-solta]');
    expect(citacao.text()).toContain('Maria');
    expect(citacao.classes()).toContain('border-s-[#5E44D8]');
    expect(citacao.find('.i-ph-camera-fill').exists()).toBe(true);
    expect(citacao.find('strong').text()).toBe('foto');
    expect(citacao.find('[data-citacao-de-outra-conversa]').text()).toBe(
      'From another conversation'
    );
    expect(citacao.find('[data-citacao-nao-conferida]').exists()).toBe(false);
  });

  it('de outra conversa, da equipe (User): "You" e faixa verde', () => {
    const wrapper = montar({
      contentAttributes: {
        quotedMessage: { ...deOutraConversa, senderType: 'User' },
      },
    });
    const citacao = wrapper.find('[data-citacao-solta]');
    expect(citacao.text()).toContain('You');
    expect(citacao.text()).not.toContain('Maria');
    expect(citacao.classes()).toContain('border-s-[#1A6B42]');
    expect(citacao.find('[data-citacao-nao-conferida]').exists()).toBe(false);
  });

  it('não deixa clicar: nenhum evento de ir até a mensagem', async () => {
    const wrapper = montar({
      contentAttributes: { quotedMessage: deOutraConversa },
    });
    const citacao = wrapper.findComponent({ name: 'CitacaoDoWhatsapp' });
    await citacao.trigger('click');
    await citacao.trigger('keydown', { key: 'Enter' });
    expect(citacao.emitted('ir')).toBeUndefined();
  });

  it('com in_reply_to (mesma conversa) a citação de sempre vence', () => {
    const wrapper = montar({
      inReplyTo: {
        id: 2,
        content: 'Antes',
        messageType: MESSAGE_TYPES.INCOMING,
        sender: { name: 'Maria' },
      },
      contentAttributes: { quotedMessage: naoAchada },
    });
    expect(wrapper.find('[data-citacao-solta]').exists()).toBe(false);
    expect(wrapper.find('[role="button"]').text()).toContain('Antes');
  });

  it('sem a pele, nada muda', () => {
    const wrapper = montar(
      { contentAttributes: { quotedMessage: deOutraConversa } },
      { pele: null }
    );
    expect(wrapper.find('[data-citacao-solta]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Olha a');
  });

  it('a leitura da chave: empresa, cliente, tipo e ausência', () => {
    expect(citacaoSolta({})).toBeNull();
    expect(citacaoSolta({ quotedMessage: 'x' })).toBeNull();
    expect(citacaoSolta({ quotedMessage: deOutraConversa })).toEqual({
      naoConferida: false,
      daEmpresa: false,
      texto: 'Olha a *foto*',
      anexo: 'image',
      outraConversa: true,
    });
    expect(
      citacaoSolta({
        quotedMessage: {
          messageId: 3,
          senderType: 'User',
          attachmentType: 'x',
        },
      })
    ).toMatchObject({ daEmpresa: true, anexo: null, outraConversa: false });
    // fromMe só vale sem unverified: com ela, não é da empresa.
    expect(citacaoSolta({ quotedMessage: naoAchada })).toMatchObject({
      naoConferida: true,
      daEmpresa: false,
      anexo: 'midia',
    });
    expect(
      citacaoSolta({ quotedMessage: { ...naoAchada, unverified: undefined } })
    ).toMatchObject({ naoConferida: false, daEmpresa: true });
  });
});

describe('2. mídia que não baixou (media_unavailable)', () => {
  const falhou = (kind, extras = {}) => ({
    content: 'Foto não pôde ser baixada. Peça para o cliente reenviar.',
    contentAttributes: {
      mediaUnavailable: {
        kind,
        reason: 'download_failed',
        at: '2026-10-16T18:00:00Z',
        ...extras,
      },
    },
  });

  it.each([
    ['image', "Couldn't download this photo", 'i-ph-camera'],
    ['video', "Couldn't download this video", 'i-ph-video-camera'],
    ['voice', "Couldn't download this voice message", 'i-ph-microphone'],
    ['audio', "Couldn't download this audio", 'i-ph-headphones'],
    ['document', "Couldn't download this document", 'i-ph-file'],
    ['sticker', "Couldn't download this sticker", 'i-ph-sticker'],
  ])(
    '%s: aviso cinza com o ícone do tipo e o texto embaixo',
    (tipo, texto, icone) => {
      const wrapper = montar(falhou(tipo));
      const cartao = balao(wrapper, 'midia-indisponivel');
      expect(cartao.exists()).toBe(true);
      expect(
        cartao.find(`[data-midia-indisponivel="${tipo}"]`).text()
      ).toContain(texto);
      expect(cartao.find(`.${icone}`).exists()).toBe(true);
      expect(cartao.find('[data-texto-da-midia-indisponivel]').text()).toBe(
        'Foto não pôde ser baixada. Peça para o cliente reenviar.'
      );
    }
  );

  it('tipo desconhecido vira documento; hasCaption false esconde o aviso repetido', () => {
    const wrapper = montar(falhou('gif', { hasCaption: false }));
    expect(wrapper.find('[data-midia-indisponivel="document"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-texto-da-midia-indisponivel]').exists()).toBe(
      false
    );
    expect(midiaIndisponivel({ mediaUnavailable: null })).toBeNull();
  });

  it('sem a pele, o texto de sempre', () => {
    const wrapper = montar(falhou('image'), { pele: null });
    expect(balao(wrapper, 'midia-indisponivel').exists()).toBe(false);
    expect(balao(wrapper, 'text').text()).toContain(
      'Foto não pôde ser baixada'
    );
  });
});

describe('3. localização (shared_location)', () => {
  const anexo = {
    id: 5,
    fileType: 'location',
    coordinatesLat: -23.56,
    coordinatesLong: -46.65,
    fallbackTitle: 'Padaria Central, Rua A, 10',
  };
  const local = (extras = {}) => ({
    latitude: -23.56,
    longitude: -46.65,
    name: 'Padaria Central',
    address: 'Rua A, 10',
    ...extras,
  });

  it('nome e endereço em linhas próprias; sem live, sem aviso', () => {
    const wrapper = montar({
      content: null,
      attachments: [anexo],
      contentAttributes: { sharedLocation: local() },
    });
    const cartao = balao(wrapper, 'received-location');
    expect(cartao.find('[data-titulo-do-cartao]').text()).toBe(
      'Padaria Central'
    );
    expect(cartao.text()).toContain('Rua A, 10');
    expect(cartao.find('[data-aviso-do-cartao]').exists()).toBe(false);
  });

  it('live: legenda "Live location · starting point only"', () => {
    const wrapper = montar({
      content: null,
      attachments: [anexo],
      contentAttributes: { sharedLocation: local({ live: true }) },
    });
    expect(wrapper.find('[data-aviso-do-cartao]').text()).toBe(
      'Live location · starting point only'
    );
  });

  it('só a chave, sem o anexo: o cartão sai da chave', () => {
    const wrapper = montar({
      content: null,
      attachments: [],
      contentAttributes: { sharedLocation: local({ live: true }) },
    });
    const cartao = balao(wrapper, 'received-location');
    expect(cartao.find('[data-titulo-do-cartao]').text()).toBe(
      'Padaria Central'
    );
    expect(cartao.find('[data-aviso-do-cartao]').exists()).toBe(true);
  });

  it('sem a pele: o cartão da main, sem a legenda do ao vivo', () => {
    const wrapper = montar(
      {
        content: null,
        attachments: [anexo],
        contentAttributes: { sharedLocation: local({ live: true }) },
      },
      { pele: null }
    );
    expect(balao(wrapper, 'received-location').text()).toContain(
      'Padaria Central'
    );
    expect(wrapper.find('[data-aviso-do-cartao]').exists()).toBe(false);
  });
});

describe('4. contatos (shared_contacts)', () => {
  const contato = (id, firstName, lastName, telefone) => ({
    id,
    fileType: 'contact',
    fallbackTitle: telefone,
    meta: { firstName, lastName },
  });
  const tres = {
    attachments: [
      contato(1, 'Ana', 'Souza', '+55 11 99999-0001'),
      contato(2, 'Ana', 'Souza', '+55 11 3333-0001'),
      contato(3, 'Bruno', undefined, '+55 21 98888-0002'),
      contato(4, 'Carla', 'Lima', '+55 31 97777-0003'),
    ],
    contentAttributes: {
      sharedContacts: [
        {
          fullName: 'Ana Souza',
          phones: ['+55 11 99999-0001', '+55 11 3333-0001'],
          waId: '5511999990001',
        },
        { fullName: 'Bruno', phones: ['+55 21 98888-0002'], waId: null },
        {
          fullName: 'Carla Lima',
          phones: ['+55 31 97777-0003'],
          waId: '5531977770003',
        },
      ],
    },
  };

  it('"Ana Souza and 2 other contacts" (por contato, não por telefone) e a lista com os telefones', async () => {
    const wrapper = montar({ content: null, ...tres });
    expect(wrapper.find('[data-resumo-dos-contatos]').text()).toBe(
      'Ana Souza and 2 other contacts'
    );
    await wrapper.find('[data-ver-todos-os-contatos]').trigger('click');
    const itens = wrapper.findAll('[data-lista-de-contatos] li');
    expect(itens).toHaveLength(3);
    expect(itens[0].text()).toContain('+55 11 99999-0001');
    expect(itens[0].text()).toContain('+55 11 3333-0001');
    expect(wrapper.find('[data-ver-todos-os-contatos]').classes()).toContain(
      'h-11'
    );
  });

  it('um contato com dois telefones fica no cartão de um contato', () => {
    const wrapper = montar({
      content: null,
      attachments: tres.attachments.slice(0, 2),
      contentAttributes: {
        sharedContacts: tres.contentAttributes.sharedContacts.slice(0, 1),
      },
    });
    expect(wrapper.find('[data-contatos-do-whatsapp]').exists()).toBe(false);
    expect(balao(wrapper, 'contact-acao').text()).toContain('Ana Souza');
  });

  it('"Conversar" usa o waId do dono do telefone; sem waId, o telefone', () => {
    const { contentAttributes } = tres;
    expect(numeroParaConversar('+55 11 3333-0001', contentAttributes)).toBe(
      '5511999990001'
    );
    expect(numeroParaConversar('+55 21 98888-0002', contentAttributes)).toBe(
      '5521988880002'
    );
    // Um contato só: o waId dele, mesmo com o telefone escrito de outro jeito.
    expect(
      numeroParaConversar('011 99999-0001', {
        sharedContacts: [
          { fullName: 'Ana', phones: [], waId: '5511999990001' },
        ],
      })
    ).toBe('5511999990001');
    expect(numeroParaConversar('+55 11 1234-5678', {})).toBe('551112345678');
  });

  it('sem shared_contacts, os anexos de sempre', () => {
    const anexos = tres.attachments.slice(2);
    expect(variosContatos(anexos, {})).toBe(true);
    expect(contatosDoBalao(anexos, {}).map(item => item.nome)).toEqual([
      'Bruno',
      'Carla Lima',
    ]);
  });

  it('sem a pele, nada do cartão do app', () => {
    const wrapper = montar({ content: null, ...tres }, { pele: null });
    expect(wrapper.find('[data-contatos-do-whatsapp]').exists()).toBe(false);
  });
});

describe('5. mensagens temporárias (waha_ephemeral)', () => {
  const aviso = expirationSeconds => ({
    messageType: MESSAGE_TYPES.ACTIVITY,
    content:
      'Mensagens temporárias ativadas (7 dias). O conteúdo fica guardado.',
    sender: null,
    contentAttributes: {
      wahaEphemeral: { expirationSeconds, at: '2026-10-16T18:00:00Z' },
    },
  });

  it.each([
    [604800, 'after 7 days.'],
    [7776000, 'after 90 days.'],
    [86400, 'after 24 hours.'],
  ])('%i s: "…disappear from this chat %s"', (segundos, fim) => {
    const wrapper = montar(aviso(segundos));
    const etiqueta = wrapper.find('[data-aviso-de-temporarias="ligadas"]');
    expect(etiqueta.text()).toContain(
      `Disappearing messages are on. New messages will disappear from this chat ${fim}`
    );
    expect(etiqueta.find('.i-ph-timer').exists()).toBe(true);
    expect(etiqueta.find('[data-temporarias-guardadas]').exists()).toBe(true);
  });

  it('0: desativadas, sem a linha de guardadas', () => {
    const etiqueta = montar(aviso(0)).find(
      '[data-aviso-de-temporarias="desligadas"]'
    );
    expect(etiqueta.text()).toBe('Disappearing messages are off.');
    expect(etiqueta.find('[data-temporarias-guardadas]').exists()).toBe(false);
  });

  it('valor estranho não vira aviso', () => {
    expect(
      avisoDeTemporarias({ wahaEphemeral: { expirationSeconds: '7' } })
    ).toBeNull();
    expect(avisoDeTemporarias({})).toBeNull();
  });

  it('sem a pele, a atividade de sempre, com o texto do servidor', () => {
    const wrapper = montar(aviso(604800), { pele: null });
    expect(wrapper.find('[data-aviso-de-temporarias]').exists()).toBe(false);
    expect(balao(wrapper, 'activity').text()).toContain(
      'Mensagens temporárias ativadas (7 dias)'
    );
  });
});

describe('6. áudio de voz (is_voice_message)', () => {
  const montarAudio = attachment =>
    mount(
      defineComponent({
        setup() {
          provideMessageContext({
            sender: ref({ name: 'Ana' }),
            orientation: ref('left'),
            contentAttributes: ref({}),
          });
          return () => h(AudioDoWhatsapp, { attachment });
        },
      }),
      {
        global: {
          plugins: [createStore({ getters: {} }), i18n()],
          stubs: { Avatar: true },
        },
      }
    );

  it('aceita a marca no meta (WAHA) e no anexo (caixa de resposta)', () => {
    expect(audioDeVoz({ meta: { isVoiceMessage: true } })).toBe(true);
    expect(audioDeVoz({ isVoiceMessage: true })).toBe(true);
    expect(audioDeVoz({ meta: {} })).toBe(false);
  });

  it('a voz marcada tem o desenho de voz (foto com o microfone)', () => {
    const wrapper = montarAudio({
      dataUrl: 'https://x.test/audio-20261016-180000.ogg',
      meta: { isVoiceMessage: true },
    });
    expect(wrapper.find('[data-audio-de-voz]').exists()).toBe(true);
    expect(wrapper.find('.i-ph-microphone-fill').exists()).toBe(true);
  });

  it('sem a marca, o mesmo desenho de antes, sem o registro de voz', () => {
    const wrapper = montarAudio({ dataUrl: 'https://x.test/a.ogg' });
    expect(wrapper.find('[data-audio-do-whatsapp]').exists()).toBe(true);
    expect(wrapper.find('[data-audio-de-voz]').exists()).toBe(false);
  });

  it('áudio-arquivo (is_voice_message false): fone de ouvido no lugar da foto', () => {
    const wrapper = montarAudio({
      dataUrl: 'https://x.test/musica.mp3',
      meta: { isVoiceMessage: false },
    });
    expect(wrapper.find('[data-audio-arquivo]').exists()).toBe(true);
    expect(wrapper.find('.i-ph-headphones-fill').exists()).toBe(true);
    expect(wrapper.find('.i-ph-microphone-fill').exists()).toBe(false);
  });

  it('sem marca nenhuma, continua voz (sem o fone de ouvido)', () => {
    const wrapper = montarAudio({ dataUrl: 'https://x.test/a.ogg' });
    expect(wrapper.find('[data-audio-arquivo]').exists()).toBe(false);
    expect(wrapper.find('.i-ph-microphone-fill').exists()).toBe(true);
  });

  it('sem a pele, o tocador de sempre', () => {
    const wrapper = montar(
      {
        content: null,
        attachments: [
          {
            id: 9,
            fileType: 'audio',
            dataUrl: 'https://x.test/a.ogg',
            meta: { isVoiceMessage: true },
          },
        ],
      },
      { pele: null }
    );
    expect(wrapper.find('[data-audio-do-whatsapp]').exists()).toBe(false);
  });
});

describe('7. pedido sem itens (WAHA)', () => {
  const order = {
    items: [],
    orderId: '8812',
    itemCount: 3,
    totalAmount: '150.00',
    currency: 'BRL',
    title: 'Loja da Ana',
    text: 'Pode mandar hoje?',
  };

  it('título, "3 items", total na moeda e sem "Ver pedido"', () => {
    const cartao = balao(
      montar({ content: null, contentAttributes: { order } }),
      'pedido'
    );
    expect(cartao.find('[data-titulo-do-pedido]').text()).toBe('Loja da Ana');
    expect(cartao.find('[data-resumo-do-pedido]').text()).toBe(
      '3 items · R$150.00'
    );
    expect(cartao.text()).toContain('Pode mandar hoje?');
    expect(cartao.find('[data-ver-pedido]').exists()).toBe(false);
  });

  it('sem título, "Order"; total que não é número fica de fora', () => {
    const cartao = balao(
      montar({
        content: null,
        contentAttributes: {
          order: { ...order, title: '', totalAmount: '150,00' },
        },
      }),
      'pedido'
    );
    expect(cartao.find('[data-titulo-do-pedido]').text()).toBe('Order');
    expect(cartao.find('[data-resumo-do-pedido]').text()).toBe('3 items');
  });

  it('a leitura do pedido sem itens', () => {
    expect(ehPedido({ order })).toBe(true);
    expect(ehPedido({ order: { items: [] } })).toBe(false);
    expect(resumoDoPedido({ ...order, items: undefined })).toEqual({
      itens: [],
      unidades: 3,
      total: 150,
      moeda: 'BRL',
    });
    expect(resumoDoPedido({ ...order, totalAmount: '' }).total).toBeNull();
  });

  it('sem a pele, sem cartão', () => {
    const wrapper = montar(
      { content: 'pedido', contentAttributes: { order } },
      { pele: null }
    );
    expect(balao(wrapper, 'pedido').exists()).toBe(false);
  });
});

describe('8. tipo rico desconhecido (event)', () => {
  const evento = {
    content: 'Reunião de proposta',
    messageType: MESSAGE_TYPES.OUTGOING,
    sender: { id: 1, name: 'Ana', type: 'User' },
    contentAttributes: {
      richMessage: {
        type: 'event',
        startAt: '2026-10-20T14:00:00-03:00',
        locationName: 'Escritório',
      },
    },
  };

  it.each([PELES.WHATSAPP, null])(
    'pele %s: a mensagem continua aparecendo com o texto',
    pele => {
      const wrapper = montar(evento, { pele });
      expect(wrapper.find('[data-bubble-name]').exists()).toBe(true);
      expect(wrapper.text()).toContain('Reunião de proposta');
    }
  );
});
