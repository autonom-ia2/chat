import { getters } from '../../inboxes';

// Formato real da Meta (GET /message_templates), como a caixa guarda.
const corpo = { type: 'BODY', text: 'Olá {{1}}, veja o que separamos.' };

const normal = {
  name: 'boas_vindas',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'UTILITY',
  components: [
    { type: 'HEADER', format: 'IMAGE' },
    corpo,
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'QUICK_REPLY', text: 'Quero' },
        { type: 'URL', text: 'Site', url: 'https://exemplo.com/{{1}}' },
      ],
    },
  ],
};

const umProduto = {
  name: 'produto_unico',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'PRODUCT' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] },
  ],
};

const variosProdutos = {
  name: 'lista_de_produtos',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'TEXT', text: 'Novidades' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'MPM', text: 'Ver itens' }] },
  ],
};

const carrosselDeProdutos = {
  name: 'carrossel_de_produtos',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  components: [
    corpo,
    {
      type: 'CAROUSEL',
      cards: [0, 1].map(() => ({
        components: [
          { type: 'HEADER', format: 'PRODUCT' },
          { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] },
        ],
      })),
    },
  ],
};

const carrosselDeMidia = {
  name: 'carrossel_de_fotos',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  components: [
    corpo,
    {
      type: 'CAROUSEL',
      cards: [0, 1].map(() => ({
        components: [
          { type: 'HEADER', format: 'IMAGE' },
          { type: 'BODY', text: 'Cartão' },
          {
            type: 'BUTTONS',
            buttons: [{ type: 'QUICK_REPLY', text: 'Quero este' }],
          },
        ],
      })),
    },
  ],
};

const estadoCom = templates => ({
  records: [
    { id: 7, channel_type: 'Channel::Whatsapp', message_templates: templates },
  ],
});

const daConversa = (state, inboxId, opcoes) =>
  getters.getConversationWhatsAppTemplates(state, {
    getFilteredWhatsAppTemplates: getters.getFilteredWhatsAppTemplates(state),
  })(inboxId, opcoes);

describe('inboxes/getConversationWhatsAppTemplates (#1703)', () => {
  const todos = [
    normal,
    umProduto,
    variosProdutos,
    carrosselDeProdutos,
    carrosselDeMidia,
  ];

  it('the upstream filter lets the real Meta product and carousel formats through', () => {
    const nomes = getters
      .getFilteredWhatsAppTemplates(estadoCom(todos))(7)
      .map(template => template.name);

    expect(nomes).toEqual(todos.map(template => template.name));
  });

  it('keeps only what a conversation can send', () => {
    const nomes = daConversa(estadoCom(todos), 7).map(
      template => template.name
    );

    expect(nomes).toEqual(['boas_vindas']);
  });

  it.each([
    ['topo PRODUCT + SPM', umProduto],
    ['MPM', variosProdutos],
    ['carrossel de produtos', carrosselDeProdutos],
    ['carrossel de mídia', carrosselDeMidia],
    [
      'topo PRODUCT sem botão',
      { ...umProduto, components: [umProduto.components[0], corpo] },
    ],
    [
      'botão CATALOG',
      {
        ...normal,
        name: 'catalogo',
        components: [
          corpo,
          {
            type: 'BUTTONS',
            buttons: [{ type: 'CATALOG', text: 'Ver catálogo' }],
          },
        ],
      },
    ],
  ])('hides %s', (_rotulo, template) => {
    expect(daConversa(estadoCom([template]), 7)).toEqual([]);
  });

  it('keeps coupon (COPY_CODE) and limited-time offer templates, which the conversation fills', () => {
    const cupom = {
      ...normal,
      name: 'cupom',
      components: [
        corpo,
        {
          type: 'BUTTONS',
          buttons: [{ type: 'COPY_CODE', example: ['CUPOM10'] }],
        },
      ],
    };
    const oferta = {
      ...normal,
      name: 'oferta',
      components: [
        { type: 'LIMITED_TIME_OFFER', limited_time_offer: { text: 'Só hoje' } },
        corpo,
      ],
    };

    expect(daConversa(estadoCom([cupom, oferta]), 7)).toEqual([cupom, oferta]);
  });

  it('reads the structure in any case, like the server', () => {
    const minusculo = {
      ...variosProdutos,
      components: [
        corpo,
        { type: 'buttons', buttons: [{ type: 'mpm', text: 'Ver itens' }] },
      ],
    };

    expect(daConversa(estadoCom([minusculo, normal]), 7)).toEqual([normal]);
  });

  it('still applies the upstream rules (not approved, authentication)', () => {
    const pendente = { ...normal, name: 'pendente', status: 'PENDING' };
    const codigo = { ...normal, name: 'codigo', category: 'AUTHENTICATION' };

    expect(daConversa(estadoCom([pendente, codigo, normal]), 7)).toEqual([
      normal,
    ]);
  });

  it('returns an empty list for an inbox without templates', () => {
    expect(daConversa({ records: [{ id: 8 }] }, 8)).toEqual([]);
  });
});

// #1716: a escolha de modelo da conversa pede os que ela sabe completar.
describe('inboxes/getConversationWhatsAppTemplates with what the conversation completes (#1716)', () => {
  const todos = [
    normal,
    umProduto,
    variosProdutos,
    carrosselDeProdutos,
    carrosselDeMidia,
  ];
  const nomes = opcoes =>
    daConversa(estadoCom(todos), 7, opcoes).map(template => template.name);

  it('offers products and the photo carousel when both are complete', () => {
    expect(nomes({ completa: { fotos: true, produtos: true } })).toEqual(
      todos.map(template => template.name)
    );
  });

  it('products only with the products flag', () => {
    expect(nomes({ completa: { fotos: true, produtos: false } })).toEqual([
      'boas_vindas',
      'carrossel_de_fotos',
    ]);
  });

  it('without completa (new conversation, CRM, booking) as before', () => {
    expect(nomes(undefined)).toEqual(['boas_vindas']);
    expect(nomes({})).toEqual(['boas_vindas']);
  });

  it('still hides what the screen cannot complete (catalog button, video carousel)', () => {
    const catalogo = {
      ...normal,
      name: 'catalogo',
      components: [
        corpo,
        { type: 'BUTTONS', buttons: [{ type: 'CATALOG', text: 'Catálogo' }] },
      ],
    };
    const video = {
      ...carrosselDeMidia,
      name: 'carrossel_de_videos',
      components: [
        corpo,
        {
          type: 'CAROUSEL',
          cards: [0, 1].map(() => ({
            components: [
              { type: 'HEADER', format: 'VIDEO' },
              { type: 'BODY', text: 'Cartão' },
            ],
          })),
        },
      ],
    };
    const completa = { completa: { fotos: true, produtos: true } };

    expect(daConversa(estadoCom([catalogo, video]), 7, completa)).toEqual([]);
  });
});
