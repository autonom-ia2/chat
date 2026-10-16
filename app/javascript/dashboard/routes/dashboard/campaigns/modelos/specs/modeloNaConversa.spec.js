import {
  camposDoContato,
  cartaoPronto,
  cartoesDoModelo,
  comEspacos,
  comEstoqueRelido,
  exemploDoCampo,
  faltaNoCorpo,
  montarEnvio,
  moverProduto,
  tipoNaConversa,
} from '../conversa/modeloNaConversa';
import { perfilDaLista } from '../conversa/perfilDoModelo';
import { produtoDaApi } from '../api/adaptadorHttp';

// Formato real da Meta (GET /message_templates), como a caixa guarda (#1716).
// developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/
// {spm,mpm,product-card-carousel}-template-messages e .../templates/
// marketing-templates/media-card-carousel-templates.
const corpo = {
  type: 'BODY',
  text: 'Oi {{1}}, separei {{2}} para você.',
  example: { body_text: [['Ana', 'novidades']] },
};
const base = {
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  namespace: 'ns',
};
const umProduto = {
  ...base,
  name: 'produto_em_destaque',
  components: [
    { type: 'HEADER', format: 'PRODUCT' },
    corpo,
    { type: 'FOOTER', text: 'Loja Exemplo' },
    { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] },
  ],
};
const varios = {
  ...base,
  name: 'vitrine_da_semana',
  components: [
    { type: 'HEADER', format: 'TEXT', text: 'Novidades' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'MPM', text: 'Ver itens' }] },
  ],
};
const carrosselDeProdutos = {
  ...base,
  name: 'carrossel_de_produtos',
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
const cartaoDeFoto = (
  texto,
  botoes = [{ type: 'QUICK_REPLY', text: 'Quero' }]
) => ({
  components: [
    {
      type: 'HEADER',
      format: 'IMAGE',
      example: { header_handle: ['https://scontent/1.jpg'] },
    },
    { type: 'BODY', text: texto, example: { body_text: [['20%']] } },
    { type: 'BUTTONS', buttons: botoes },
  ],
});
const fotos = {
  ...base,
  name: 'ofertas_da_semana',
  components: [
    { type: 'BODY', text: 'Oi {{1}}, veja as ofertas.' },
    {
      type: 'CAROUSEL',
      cards: [cartaoDeFoto('Tênis com {{1}} off'), cartaoDeFoto('Mochila')],
    },
  ],
};

describe('tipoNaConversa (#1716)', () => {
  it.each([
    ['um produto (topo PRODUCT + SPM)', umProduto, 'um'],
    ['vários produtos (MPM)', varios, 'varios'],
    ['carrossel de produtos', carrosselDeProdutos, 'carrossel'],
    ['carrossel de fotos', fotos, 'cartoes'],
  ])('%s', (_rotulo, template, tipo) => {
    expect(tipoNaConversa(template)).toBe(tipo);
  });

  it.each([
    ['modelo comum', { ...base, components: [corpo] }],
    [
      'MPM com campo no título',
      {
        ...varios,
        components: [
          { type: 'HEADER', format: 'TEXT', text: 'Para {{1}}' },
          ...varios.components.slice(1),
        ],
      },
    ],
    [
      'carrossel de vídeo',
      {
        ...fotos,
        components: [
          corpo,
          {
            type: 'CAROUSEL',
            cards: [0, 1].map(() => ({
              components: [{ type: 'HEADER', format: 'VIDEO' }],
            })),
          },
        ],
      },
    ],
    [
      'cartão com link que tem campo',
      {
        ...fotos,
        components: [
          corpo,
          {
            type: 'CAROUSEL',
            cards: [
              cartaoDeFoto('Tênis', [
                { type: 'URL', text: 'Ver', url: 'https://loja.com/{{1}}' },
              ]),
              cartaoDeFoto('Mochila'),
            ],
          },
        ],
      },
    ],
    [
      'oferta por tempo limitado junto do produto',
      {
        ...umProduto,
        components: [
          { type: 'LIMITED_TIME_OFFER', limited_time_offer: { text: 'Hoje' } },
          ...umProduto.components,
        ],
      },
    ],
    [
      'botão de cupom junto do MPM',
      {
        ...varios,
        components: [
          ...varios.components.slice(0, 2),
          {
            type: 'BUTTONS',
            buttons: [
              { type: 'MPM', text: 'Ver itens' },
              { type: 'COPY_CODE', example: ['CUPOM'] },
            ],
          },
        ],
      },
    ],
  ])('fora da conversa: %s', (_rotulo, template) => {
    expect(tipoNaConversa(template)).toBe('');
  });

  it('lê a estrutura em qualquer caixa, como o servidor', () => {
    const minusculo = {
      ...varios,
      components: [
        corpo,
        { type: 'buttons', buttons: [{ type: 'mpm', text: 'Ver itens' }] },
      ],
    };
    expect(tipoNaConversa(minusculo)).toBe('varios');
  });
});

describe('campos e texto', () => {
  it('o exemplo da Meta de cada campo, posicional ou com nome', () => {
    expect(exemploDoCampo(corpo, '2')).toBe('novidades');
    const nomeado = {
      text: 'Oi {{nome}}',
      example: {
        body_text_named_params: [{ param_name: 'nome', example: 'Ana' }],
      },
    };
    expect(exemploDoCampo(nomeado, 'nome')).toBe('Ana');
  });

  it('espaço vazio aparece com o rótulo, nunca como {{1}}', () => {
    expect(comEspacos(corpo.text, { 1: 'Bia' }, n => `[espaço ${n}]`)).toBe(
      'Oi Bia, separei [espaço 2] para você.'
    );
  });

  it('diz o que falta no corpo e quando um cartão está pronto', () => {
    expect(faltaNoCorpo(umProduto, { 1: 'Ana', 2: '  ' })).toEqual(['2']);
    const [cartao] = cartoesDoModelo(fotos);
    expect(cartao.campos).toEqual(['1']);
    expect(cartaoPronto(cartao, { referencia: 'r1', campos: {} })).toBe(false);
    expect(
      cartaoPronto(cartao, { referencia: 'r1', campos: { 1: '20%' } })
    ).toBe(true);
    expect(cartaoPronto(cartao, { campos: { 1: '20%' } })).toBe(false);
  });
});

describe('camposDoContato: o nome do cliente sozinho, como na campanha', () => {
  const perfil = { 1: 'cliente.primeiro_nome', 2: 'data' };

  it('preenche o primeiro nome do contato pelo perfil do modelo', () => {
    expect(
      camposDoContato(umProduto, perfil, { name: '  Marina Costa Lima ' })
    ).toEqual({ 1: 'Marina' });
  });

  it('nome que é só telefone fica vazio (nunca "Oi, +55 11 9…")', () => {
    expect(
      camposDoContato(umProduto, perfil, { name: '+55 (11) 99999-0000' })
    ).toEqual({});
  });

  it('sem perfil, nada é preenchido', () => {
    expect(camposDoContato(umProduto, {}, { name: 'Marina' })).toEqual({});
  });
});

describe('ordem e estoque dos produtos', () => {
  const lista = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];

  it('subir e descer trocam vizinhos e param nas pontas', () => {
    expect(moverProduto(lista, 2, -1).map(item => item.id)).toEqual([
      'a',
      'c',
      'b',
    ]);
    expect(moverProduto(lista, 0, -1)).toBe(lista);
    expect(moverProduto(lista, 2, 1)).toBe(lista);
  });

  it('o que acabou ou saiu do catálogo fica indisponível', () => {
    const relidos = [
      { id: 'a', disponivel: true },
      { id: 'b', disponivel: false },
    ];
    expect(
      comEstoqueRelido(lista, relidos).map(item => item.disponivel)
    ).toEqual([true, false, false]);
  });

  it('promoção dentro do período: o preço que o cliente vê e o cheio riscado', () => {
    const api = {
      id: 'tenis',
      name: 'Tênis',
      price: 'R$ 299,90',
      sale_price: 'R$ 249,90',
      image_url: 'https://cdn/t.jpg',
      available: true,
    };
    expect(produtoDaApi(api)).toMatchObject({
      preco: 'R$ 249,90',
      precoAntes: 'R$ 299,90',
    });
    expect(produtoDaApi({ ...api, sale_price: '' })).toMatchObject({
      preco: 'R$ 299,90',
      precoAntes: '',
    });
  });
});

describe('montarEnvio: o processed_params da campanha', () => {
  const tenis = { id: 'tenis', nome: 'Tênis', disponivel: true };
  const mochila = { id: 'mochila', nome: 'Mochila', disponivel: true };

  it('vários produtos: os códigos na ordem e os nomes, sem catálogo', () => {
    const envio = montarEnvio({
      template: varios,
      tipo: 'varios',
      corpo: { 1: 'Ana', 2: 'novidades' },
      produtos: [mochila, tenis],
      cartoes: {},
    });
    expect(envio.message).toBe('Oi Ana, separei novidades para você.');
    expect(envio.templateParams).toEqual({
      name: 'vitrine_da_semana',
      category: 'MARKETING',
      language: 'pt_BR',
      namespace: 'ns',
      content_mode: 'raw_template',
      processed_params: {
        body: { 1: 'Ana', 2: 'novidades' },
        products: {
          retailer_ids: ['mochila', 'tenis'],
          names: { mochila: 'Mochila', tenis: 'Tênis' },
        },
      },
    });
  });

  it('carrossel de fotos: um cartão por cartão do modelo, com o arquivo escolhido', () => {
    const envio = montarEnvio({
      template: fotos,
      tipo: 'cartoes',
      corpo: { 1: 'Ana' },
      produtos: [],
      cartoes: {
        0: { referencia: 'blob-1', campos: { 1: '20%' } },
        1: { referencia: 'blob-2', campos: {} },
      },
    });
    expect(envio.templateParams.processed_params).toEqual({
      body: { 1: 'Ana' },
      carousel: {
        cards: [
          { header: { media_blob: 'blob-1' }, body: { 1: '20%' } },
          { header: { media_blob: 'blob-2' }, body: {} },
        ],
      },
    });
  });
});

describe('perfilDaLista: galeria e campos do perfil do modelo', () => {
  it('as fotos aprovadas de cada cartão, com miniatura e referência', () => {
    const lista = [
      {
        name: 'ofertas_da_semana',
        language: 'pt_BR',
        fields: { 1: 'cliente.primeiro_nome' },
        card_media: [
          {
            card_index: 0,
            file_name: 'a.jpg',
            preview_url: 'https://s/a',
            blob_signed_id: 'b1',
          },
          { card_index: 1, file_name: 'v.mp4' },
        ],
      },
    ];
    expect(perfilDaLista(lista, fotos)).toEqual({
      campos: { 1: 'cliente.primeiro_nome' },
      galeria: [
        { url: 'https://s/a', referencia: 'b1', nome: 'a.jpg', cartao: 0 },
      ],
      falhou: false,
    });
    expect(perfilDaLista([], fotos)).toEqual({
      campos: {},
      galeria: [],
      falhou: false,
    });
  });
});
