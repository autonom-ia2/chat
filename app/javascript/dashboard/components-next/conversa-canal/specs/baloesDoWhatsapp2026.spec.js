/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import MessageList from '../../message/MessageList.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import TiquesDoWhatsapp from '../TiquesDoWhatsapp.vue';
import CitacaoDoWhatsapp from '../CitacaoDoWhatsapp.vue';
import { EMOJI, temBico } from '../visualWhatsapp';
import { ocultaNaPele } from '../marcasDaMensagem';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

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

// O texto de cada parte do item, separado por " | ".
const partes = item =>
  item
    .findAll('span')
    .map(parte => parte.text().trim())
    .join(' | ');

const balao = (wrapper, nome) => wrapper.find(`[data-bubble-name="${nome}"]`);

describe('apagada pelo cliente (#1702)', () => {
  const atributos = { deletedByContactAt: '2026-10-16T18:00:00Z' };

  it('com a pele, selo no topo e o conteúdo continua à vista', () => {
    const wrapper = montar({ contentAttributes: atributos });
    const selo = wrapper.find('[data-apagada-pelo-cliente]');
    expect(selo.exists()).toBe(true);
    expect(selo.text()).toContain('Deleted by the customer');
    expect(selo.classes()).toContain('italic');
    expect(selo.find('.i-ph-prohibit-bold').exists()).toBe(true);
    expect(balao(wrapper, 'text').text()).toContain('Olá');
  });

  it('sem a pele, nada muda; apagada pela equipe não ganha o selo do cliente', () => {
    expect(
      montar({ contentAttributes: atributos }, { pele: null })
        .find('[data-apagada-pelo-cliente]')
        .exists()
    ).toBe(false);
    expect(
      montar({ contentAttributes: { deleted: true } })
        .find('[data-apagada-pelo-cliente]')
        .exists()
    ).toBe(false);
  });
});

describe('apagada pela equipe (#1702)', () => {
  it('com a pele, o aviso do WhatsApp no lugar do texto, de cada lado', () => {
    const recebida = balao(
      montar({ contentAttributes: { deleted: true } }),
      'apagada'
    );
    expect(recebida.text()).toContain('This message was deleted');
    expect(recebida.find('.i-ph-prohibit').exists()).toBe(true);
    const enviada = balao(
      montar({
        messageType: MESSAGE_TYPES.OUTGOING,
        sender: { id: 1, name: 'Ana', type: 'User' },
        // O texto do app só quando o canal confirmou que revogou (balaoDetalhes1702.spec).
        contentAttributes: { deleted: true, revogadaNoCanal: true },
      }),
      'apagada'
    );
    expect(enviada.text()).toContain('You deleted this message');
  });

  it('sem a pele, segue o balão do Chatwoot', () => {
    const wrapper = montar(
      { contentAttributes: { deleted: true } },
      { pele: null }
    );
    expect(balao(wrapper, 'apagada').exists()).toBe(false);
  });
});

describe('encaminhada (#1702)', () => {
  it('"Encaminhada" com uma seta, em itálico cinza, numa linha no topo', () => {
    const rotulo = montar({ contentAttributes: { forwarded: true } }).find(
      '[data-rotulo-encaminhada]'
    );
    expect(rotulo.text()).toBe('Forwarded');
    expect(rotulo.classes()).toEqual(
      expect.arrayContaining([
        'italic',
        'text-[13px]',
        'text-[#666666]',
        'dark:text-[#B5C2BC]',
      ])
    );
    expect(rotulo.find('.i-ph-arrow-bend-up-right').exists()).toBe(true);
  });

  it('com frequência: seta dupla e o texto próprio; vale para a enviada', () => {
    const rotulo = montar({
      messageType: MESSAGE_TYPES.OUTGOING,
      sender: { id: 1, name: 'Ana', type: 'User' },
      contentAttributes: { forwarded: true, frequentlyForwarded: true },
    }).find('[data-rotulo-encaminhada]');
    expect(rotulo.text()).toBe('Forwarded many times');
    expect(rotulo.find('.i-ph-arrow-bend-double-up-right').exists()).toBe(true);
  });

  it('sem a pele, sem rótulo', () => {
    expect(
      montar({ contentAttributes: { forwarded: true } }, { pele: null })
        .find('[data-rotulo-encaminhada]')
        .exists()
    ).toBe(false);
  });
});

describe('não suportada com tipo (#1702)', () => {
  const naoSuportada = unsupportedKind => ({
    content: null,
    contentAttributes: { isUnsupported: true, unsupportedKind },
  });

  it.each([
    ['poll', 'The customer sent a poll.', 'i-ph-chart-bar-horizontal'],
    ['gif', 'The customer sent a GIF.', 'i-ph-gif'],
    ['pinned', 'The customer pinned a message.', 'i-ph-push-pin'],
    ['edit', 'The customer edited a message.', 'i-ph-pencil-simple'],
    ['view_once', 'You received a view once message', 'i-ph-number-circle-one'],
    ['unknown', 'does not show here', 'i-ph-device-mobile'],
  ])('%s: texto e ícone do tipo, sem o aviso amarelo', (tipo, texto, icone) => {
    const wrapper = montar(naoSuportada(tipo));
    const tipado = balao(wrapper, 'nao-suportada-tipo');
    expect(tipado.text()).toContain(texto);
    expect(tipado.find(`.${icone}`).exists()).toBe(true);
    expect(tipado.classes()).toContain('!bg-white');
    expect(tipado.classes().join(' ')).not.toContain('border-dashed');
    expect(balao(wrapper, 'unsupported').exists()).toBe(false);
  });

  it('aviso de visualização única que o aparelho vinculado não abre (WAHA): mesmo balão', () => {
    const wrapper = montar({
      messageType: 0,
      content: 'Você recebeu uma mensagem de visualização única.',
      contentAttributes: { viewOnceUnavailable: true, viewOnceId: 'abc' },
    });
    const tipado = balao(wrapper, 'nao-suportada-tipo');
    expect(tipado.text()).toContain('only open it on your phone');
    expect(tipado.find('.i-ph-number-circle-one').exists()).toBe(true);
  });

  it('voto e aviso RECEBIDOS com c2y_hidden somem da lista (não só atividade)', () => {
    expect(
      ocultaNaPele({
        messageType: 0,
        contentAttributes: { c2yHidden: true, pollVoteAppliedTo: 9 },
      })
    ).toBe(true);
    expect(
      ocultaNaPele({
        messageType: 0,
        contentAttributes: { viewOnceUnavailable: true },
      })
    ).toBe(false);
  });

  it('sem tipo ou sem a pele, o aviso genérico de sempre', () => {
    expect(balao(montar(naoSuportada(undefined)), 'unsupported').exists()).toBe(
      true
    );
    expect(
      balao(
        montar(naoSuportada('poll'), { pele: null }),
        'unsupported'
      ).exists()
    ).toBe(true);
  });
});

describe('pedido (#1702)', () => {
  const order = {
    text: 'Pode entregar hoje?',
    items: [
      {
        productRetailerId: 'CAM-P',
        quantity: 2,
        itemPrice: 50,
        currency: 'BRL',
      },
      {
        productRetailerId: 'MEIA',
        quantity: 1,
        itemPrice: 9.9,
        currency: 'BRL',
      },
    ],
  };

  it('cartão "Pedido · N itens · total" e "Ver pedido" abre os itens', async () => {
    const wrapper = montar({ content: null, contentAttributes: { order } });
    const cartao = balao(wrapper, 'pedido');
    expect(cartao.text()).toContain('Order');
    expect(cartao.find('[data-resumo-do-pedido]').text()).toBe(
      '3 items · R$109.90'
    );
    expect(cartao.text()).toContain('Pode entregar hoje?');
    const botao = cartao.find('[data-ver-pedido]');
    expect(botao.attributes('aria-expanded')).toBe('false');
    await botao.trigger('click');
    expect(botao.attributes('aria-expanded')).toBe('true');
    const itens = cartao.findAll('[data-itens-do-pedido] li');
    expect(itens.map(partes)).toEqual([
      '2 × CAM-P | R$100.00',
      '1 × MEIA | R$9.90',
    ]);
  });

  it('sem a pele, sem cartão', () => {
    expect(
      balao(
        montar(
          { content: 'pedido', contentAttributes: { order } },
          { pele: null }
        ),
        'pedido'
      ).exists()
    ).toBe(false);
  });
});

describe('ligação (#1702)', () => {
  const ligacao = (outcome, isVideo = false) => ({
    messageType: MESSAGE_TYPES.ACTIVITY,
    content: 'Ligação',
    sender: null,
    contentAttributes: {
      wahaCallSummary: {
        callId: 'c1',
        outcome,
        isVideo,
        at: '2026-10-16T18:07:00Z',
      },
    },
  });

  it('perdida: telefone cortado e título em vermelho, com a hora', () => {
    const cartao = montar(ligacao('missed')).find('[data-ligacao-do-whatsapp]');
    const titulo = cartao.find('[data-titulo-da-ligacao]');
    expect(titulo.text()).toBe('Missed voice call');
    expect(titulo.classes()).toContain('text-[#EA0038]');
    expect(cartao.find('.i-ph-phone-x-fill').exists()).toBe(true);
    expect(cartao.text()).toContain('15:07');
    expect(cartao.attributes('aria-label')).toBe('Missed voice call, 15:07');
  });

  it('vídeo atendida e recusada', () => {
    const atendida = montar(ligacao('accepted', true)).find(
      '[data-titulo-da-ligacao]'
    );
    expect(atendida.text()).toBe('Video call');
    expect(atendida.classes()).not.toContain('text-[#EA0038]');
    expect(
      montar(ligacao('rejected', true)).find('[data-titulo-da-ligacao]').text()
    ).toBe('Declined video call');
  });

  it('sem a pele, a linha de aviso de sempre', () => {
    const wrapper = montar(ligacao('missed'), { pele: null });
    expect(wrapper.find('[data-ligacao-do-whatsapp]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Ligação');
  });
});

describe('só emoji (#1702)', () => {
  it.each([
    ['😀', 'text-[48px]'],
    ['😀😂', 'text-[40px]'],
    ['😀 😂 🙏', 'text-[32px]'],
  ])('"%s" fica grande e sem balão', (content, tamanho) => {
    const wrapper = montar({ content });
    const emoji = balao(wrapper, 'emoji');
    expect(emoji.exists()).toBe(true);
    expect(emoji.classes()).toEqual(
      expect.arrayContaining(['!bg-transparent', '!shadow-none'])
    );
    expect(emoji.find('[data-emoji-grande]').classes()).toContain(tamanho);
    expect(
      temBico({ variante: 'user', primeira: true, nomeDoBalao: EMOJI })
    ).toBe(false);
  });

  it('com texto, 4 emojis, citação ou sem a pele: balão normal', () => {
    expect(balao(montar({ content: 'oi 😀' }), 'emoji').exists()).toBe(false);
    expect(balao(montar({ content: '😀😀😀😀' }), 'emoji').exists()).toBe(
      false
    );
    expect(
      balao(
        montar({ content: '😀', contentAttributes: { inReplyTo: 9 } }),
        'emoji'
      ).exists()
    ).toBe(false);
    expect(
      balao(montar({ content: '😀' }, { pele: null }), 'emoji').exists()
    ).toBe(false);
  });
});

describe('vários contatos num balão (#1702)', () => {
  const contato = (id, firstName) => ({
    id,
    fileType: 'contact',
    fallbackTitle: `+55 11 9000-000${id}`,
    meta: { firstName },
  });
  const attachments = [
    contato(1, 'Ana'),
    contato(2, 'Bia'),
    contato(3, 'Caio'),
  ];

  it('"Fulano e mais N contatos" e "Ver todos" abre a lista', async () => {
    const cartao = balao(montar({ content: null, attachments }), 'contatos');
    expect(cartao.find('[data-resumo-dos-contatos]').text()).toBe(
      'Ana and 2 other contacts'
    );
    const botao = cartao.find('[data-ver-todos-os-contatos]');
    expect(botao.text()).toBe('View all');
    await botao.trigger('click');
    const lista = cartao.findAll('[data-lista-de-contatos] li');
    expect(lista.map(partes)).toEqual([
      'Ana | +55 11 9000-0001',
      'Bia | +55 11 9000-0002',
      'Caio | +55 11 9000-0003',
    ]);
    expect(botao.attributes('aria-expanded')).toBe('true');
  });

  it('um contato só segue o cartão de sempre', () => {
    expect(
      balao(
        montar({ content: null, attachments: [contato(1, 'Ana')] }),
        'contatos'
      ).exists()
    ).toBe(false);
  });
});

describe('enquete (#1702)', () => {
  const contentAttributes = {
    richMessage: {
      type: 'poll',
      name: 'Qual horário?',
      multipleAnswers: true,
      options: [
        { id: 1, title: 'Manhã' },
        { id: 2, title: 'Tarde' },
      ],
    },
    pollVotes: [
      {
        senderType: 'Contact',
        senderId: 7,
        options: ['Tarde'],
        at: '2026-10-16T18:30:00Z',
      },
    ],
  };

  it('pergunta, instrução, contagem, ✓ na escolhida e barra proporcional', () => {
    const enquete = balao(
      montar({
        messageType: MESSAGE_TYPES.OUTGOING,
        sender: { id: 1, name: 'Ana', type: 'User' },
        content: 'Qual horário?',
        contentAttributes,
      }),
      'enquete'
    );
    expect(enquete.text()).toContain('Qual horário?');
    expect(enquete.text()).toContain('Select one or more options');
    const [manha, tarde] = enquete.findAll('[data-opcao-da-enquete]');
    expect(manha.find('[data-escolhida]').attributes('data-escolhida')).toBe(
      'false'
    );
    expect(tarde.find('[data-escolhida]').attributes('data-escolhida')).toBe(
      'true'
    );
    expect(tarde.find('.i-ph-check-bold').exists()).toBe(true);
    expect(tarde.find('.sr-only').text()).toBe('Tarde: 1 vote');
    const barras = tarde.findAll('[data-barra-da-opcao] rect');
    expect(barras[1].attributes('width')).toBe('100%');
    expect(manha.findAll('[data-barra-da-opcao] rect')).toHaveLength(1);
  });

  it('"Ver votos" mostra quem votou em quê e a hora', async () => {
    const enquete = balao(
      montar({ content: null, contentAttributes }),
      'enquete'
    );
    const botao = enquete.find('[data-ver-votos]');
    await botao.trigger('click');
    const votos = enquete.find('[data-votos-da-enquete]');
    expect(votos.text()).toContain('Tarde · 1 vote');
    expect(votos.text()).toContain('Customer');
    expect(votos.text()).toContain('15:30');
    expect(botao.text()).toBe('Hide votes');
  });

  it('formato do conector WAHA: pergunta no texto e `multiple`', () => {
    const enquete = balao(
      montar({
        content: 'Qual dia?',
        contentAttributes: {
          richMessage: {
            type: 'poll',
            multiple: false,
            options: [{ id: 'a', title: 'Sábado' }],
          },
        },
      }),
      'enquete'
    );
    expect(enquete.text()).toContain('Qual dia?');
    expect(enquete.text()).not.toContain('Select one or more options');
  });

  it('sem a pele, sem enquete desenhada', () => {
    expect(
      balao(montar({ contentAttributes }, { pele: null }), 'enquete').exists()
    ).toBe(false);
  });
});

describe('citação de figurinha (#1702)', () => {
  it('diz "Figurinha" com a pele', () => {
    const wrapper = montar({
      content: 'que fofa',
      inReplyTo: {
        id: 9,
        content: null,
        attachments: [{ fileType: 'image', isSticker: true }],
      },
    });
    expect(wrapper.text()).toContain('Sticker');
  });
});

describe('citação com link (#1702)', () => {
  it('o link vira texto: nada focável dentro do botão, formatação mantida', () => {
    const wrapper = mount(CitacaoDoWhatsapp, {
      props: {
        mensagem: { id: 9, messageType: MESSAGE_TYPES.INCOMING },
        previa:
          '<p><strong>Veja</strong> <a href="https://exemplo.com.br">exemplo.com.br</a></p>',
      },
      global: { directives: montagem.directives },
    });
    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.find('strong').text()).toBe('Veja');
    expect(wrapper.text()).toContain('exemplo.com.br');
    expect(wrapper.attributes('role')).toBe('button');
  });
});

describe('relógio de "enviando" (#1702)', () => {
  it('no lugar dos tiques, enquanto a mensagem sai', () => {
    const relogio = mount(TiquesDoWhatsapp, {
      props: { status: MESSAGE_STATUS.PROGRESS, rotulo: 'Sending' },
    });
    expect(relogio.find('circle').exists()).toBe(true);
    expect(relogio.attributes('aria-label')).toBe('Sending');
    const tiques = mount(TiquesDoWhatsapp, {
      props: { status: MESSAGE_STATUS.SENT },
    });
    expect(tiques.find('circle').exists()).toBe(false);
  });
});

describe('selo de reações fora do balão (#1702)', () => {
  const reacoes = { reactions: [{ emoji: '👍', senderType: 'Contact' }] };

  it.each([
    [
      'localização',
      {
        content: null,
        attachments: [
          {
            id: 1,
            fileType: 'location',
            coordinatesLat: 1,
            coordinatesLong: 2,
            fallbackTitle: 'Loja',
          },
        ],
      },
      'attachment',
    ],
    [
      'figurinha',
      {
        content: null,
        attachments: [
          { id: 1, fileType: 'image', isSticker: true, dataUrl: 'x.webp' },
        ],
      },
      'sticker',
    ],
  ])('%s mostra o selo e não o corta', (_nome, props, nome) => {
    const wrapper = montar({ ...props, contentAttributes: reacoes });
    const b = balao(wrapper, nome);
    expect(b.find('[data-selo-de-reacoes]').exists()).toBe(true);
    if (nome !== 'sticker') {
      expect(b.classes()).toContain(
        '[&:has(>[data-selo-de-reacoes])]:!overflow-visible'
      );
    }
  });
});

describe('c2y_hidden (#1702)', () => {
  const doServidor = (id, extras = {}) => ({
    id,
    content: `mensagem ${id}`,
    conversation_id: 7,
    message_type: 0,
    content_type: 'text',
    status: 'sent',
    private: false,
    created_at: AGORA + id,
    sender: { id: 7, name: 'Maria', type: 'contact' },
    content_attributes: {},
    ...extras,
  });
  const lista = [
    doServidor(1),
    doServidor(2, { content_attributes: { c2y_hidden: true } }),
  ];

  const montarLista = pele =>
    mount(
      comPele(pele, () =>
        h(MessageList, { currentUserId: 1, messages: lista })
      ),
      { global: global() }
    );

  it('com a pele, a mensagem absorvida some da lista', () => {
    const wrapper = montarLista(PELES.WHATSAPP);
    expect(wrapper.find('#message1').exists()).toBe(true);
    expect(wrapper.find('#message2').exists()).toBe(false);
  });

  it('sem a pele, aparece como sempre', () => {
    expect(montarLista(null).find('#message2').exists()).toBe(true);
  });
});

describe('reação que o agente da Autonomia recebe (#1702)', () => {
  const doServidor = (id, extras = {}) => ({
    id,
    content: `mensagem ${id}`,
    conversation_id: 7,
    message_type: 0,
    content_type: 'text',
    status: 'sent',
    private: false,
    created_at: AGORA + id,
    sender: { id: 7, name: 'Maria', type: 'contact' },
    content_attributes: {},
    ...extras,
  });
  // A 1 foi reagida (selo); a 2 é a mensagem sintética que o servidor cria para o agente.
  const lista = [
    doServidor(1, {
      content_attributes: {
        reactions: [{ emoji: '👍', sender_type: 'Contact' }],
      },
    }),
    doServidor(2, {
      content: '[O cliente reagiu com 👍 a uma mensagem anterior dele]',
      content_attributes: {
        autonomia_reaction: { emoji: '👍', reacted_source_id: 'wamid.1' },
      },
    }),
    doServidor(3),
  ];

  const montarLista = (pele, firstUnreadId = null, mensagens = lista) =>
    mount(
      comPele(pele, () =>
        h(
          MessageList,
          { currentUserId: 1, messages: mensagens, firstUnreadId },
          { unreadBadge: () => h('li', { 'data-faixa-nao-lidas': '' }) }
        )
      ),
      { global: global() }
    );

  it('com a pele, a sintética some e o selo continua na reagida', () => {
    const wrapper = montarLista(PELES.WHATSAPP);
    expect(wrapper.find('#message2').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('O cliente reagiu');
    expect(wrapper.find('#message1 [data-selo-de-reacoes]').exists()).toBe(
      true
    );
  });

  it('a faixa de não lidas desce para a próxima visível quando a 1ª não lida é a sintética', () => {
    const wrapper = montarLista(PELES.WHATSAPP, 2);
    const itens = wrapper.findAll('[data-faixa-nao-lidas], [id^="message"]');
    const ordem = itens.map(item => item.attributes('id') || 'faixa');
    expect(ordem).toEqual(['message1', 'faixa', 'message3']);
  });

  it('sintética por último e não lida: sem faixa', () => {
    const wrapper = montarLista(PELES.WHATSAPP, 2, lista.slice(0, 2));
    expect(wrapper.find('[data-faixa-nao-lidas]').exists()).toBe(false);
  });

  it('sem a pele, a sintética aparece e a faixa fica nela', () => {
    const wrapper = montarLista(null, 2);
    expect(wrapper.find('#message2').exists()).toBe(true);
    const itens = wrapper.findAll('[data-faixa-nao-lidas], [id^="message"]');
    const ordem = itens.map(item => item.attributes('id') || 'faixa');
    expect(ordem).toEqual(['message1', 'faixa', 'message2', 'message3']);
  });
});
