// PROTÓTIPO #2338, só para a demo local: nada daqui vai ao PR final.
//
// Responde no lugar do servidor todas as chamadas da página Anúncios da Meta, com dados de mentira de um pequeno
// negócio ("Loja Exemplo"), para a jornada navegável mostrar cada tela cheia sem falar com a Meta nem precisar de
// linha no banco. Um interceptor no `window.axios` (o mesmo que as classes de `dashboard/api` usam) troca o
// `adapter` das chamadas conhecidas; as outras seguem para o servidor como sempre.
//
// `estado.value` vem de quem instala ({ facebook, adAccount, destinations, salesSignal, ... }): a conexão é montada
// a partir dele, e as ações de conexão (login, conta, destinos, funil, desconectar) o trocam por um novo objeto.

const LATENCIA = 400;
const CONEXAO = 'crm/meta_ads_connection';
const FORMULARIOS = 'crm/meta_ads_lead_forms';
const LINKS = 'ctwa_tracked_links';
// window[GLOBAL]: a demo instalada nesta página (evita instalar duas vezes).
const GLOBAL = '__metaDemo';

const AD_ATIVO = '120210000000001';
const AD_PAUSADO = '120210000000002';
const AD_SEM_NUMEROS = '120210000000003';
const AD_NOVO = '120210000000004';

const PAGINA = { id: '104000000000001', name: 'Loja Exemplo' };
const INSTAGRAM = {
  id: '178400000000001',
  username: 'lojaexemplo',
  name: 'Loja Exemplo',
};
const WHATSAPP = {
  id: '+5511900000001',
  name: 'Loja Exemplo',
  phone: '+5511900000001',
};
const AD_ACCOUNTS = [
  { id: 'act_1001', name: 'Loja Exemplo', recommended: true, ready: true },
  { id: 'act_1002', name: 'Loja Exemplo — antiga', ready: true },
];
const PIXELS = [
  { id: 'px_1', name: 'Site da Loja', last_fired_time: '2026-10-27T10:00:00Z' },
];

const PIPELINES = [
  {
    id: 1,
    name: 'Vendas',
    stages: [
      { id: 11, name: 'Novo contato' },
      { id: 12, name: 'Orçamento enviado' },
      { id: 13, name: 'Venda fechada' },
    ],
  },
  {
    id: 2,
    name: 'Pós-venda',
    stages: [
      { id: 21, name: 'Entrega' },
      { id: 22, name: 'Avaliação' },
    ],
  },
];

const esperar = () =>
  new Promise(resolve => {
    setTimeout(resolve, LATENCIA);
  });

const pad = value => String(value).padStart(2, '0');
const dia = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const hoje = () => dia(new Date());
const diasAtras = dias => new Date(Date.now() - dias * 86400000);
const horasAtras = horas =>
  new Date(Date.now() - horas * 3600000).toISOString();

// Imagem desenhada na hora: a demo não depende de rede para mostrar foto.
const imagem = (cor, texto) =>
  `data:image/svg+xml;utf8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600"><rect width="600" height="600" fill="${cor}"/><text x="300" y="320" font-family="sans-serif" font-size="44" fill="#fff" text-anchor="middle">${texto}</text></svg>`
  )}`;

const ok = data => ({ status: 200, data });
const falha = (status, error) => ({ status, data: { error } });

// ---------- Conexão ----------

const conexao = estado => {
  if (!estado.facebook) {
    return {
      configured: false,
      status: null,
      mode: null,
      last_checked_at: null,
      last_error: null,
    };
  }
  return {
    configured: true,
    status: 'active',
    mode: 'facebook_login',
    last_checked_at: horasAtras(1),
    last_error: null,
    verified_at: estado.adAccount ? horasAtras(2) : null,
    destinations: {
      whatsapp: Boolean(estado.destinations?.whatsapp),
      site: Boolean(estado.destinations?.site),
    },
    ad_account: estado.adAccount || null,
    pixel: estado.adAccount ? { id: 'px_1', name: 'Site da Loja' } : null,
  };
};

const payloadConexao = estado => ({
  ...conexao(estado),
  partner: { available: false },
  facebook_login: {
    available: true,
    app_id: 'demo',
    configuration_id: 'demo',
    api_version: 'v22.0',
  },
  whatsapp_portfolio: false,
  client_portfolio_id: null,
  sales_signal: { enabled: Boolean(estado.salesSignal) },
  // Sem conexão, a página abre como em produção: o resultado pelo WhatsApp, com "Conectar minha conta de anúncios".
  whatsapp_result: {
    enabled: !estado.facebook,
    official_inboxes: [
      { id: 1, name: 'WhatsApp da loja', phone: '+55 11 90000-0000' },
    ],
    ad_touch: false,
    connection_state: null,
    connection_mode: null,
  },
});

// ---------- Painel ----------

const DIAS = { '7d': 7, '30d': 30, '90d': 90 };

const ANUNCIOS = [
  {
    ad_id: AD_ATIVO,
    name: 'Promoção de verão',
    thumbnail_url: imagem('#0f766e', 'Verão'),
    spend: 412.3,
    impressions: 18240,
    link_clicks: 612,
    conversations: 48,
    quotes: 12,
    sales: 5,
    sales_value: 3890,
    cost_per_sale: 82.46,
    verdict: 'up',
  },
  {
    ad_id: AD_PAUSADO,
    name: 'Coleção nova',
    thumbnail_url: imagem('#7c3aed', 'Coleção'),
    spend: 96.4,
    impressions: 4120,
    link_clicks: 133,
    conversations: 9,
    quotes: 2,
    sales: 0,
    sales_value: 0,
    cost_per_sale: null,
    verdict: 'early',
  },
  {
    ad_id: AD_SEM_NUMEROS,
    name: 'Vídeo da loja',
    thumbnail_url: imagem('#b45309', 'Vídeo'),
    spend: 0,
    impressions: 0,
    link_clicks: 0,
    conversations: 0,
    quotes: 0,
    sales: 0,
    sales_value: 0,
    cost_per_sale: null,
    verdict: 'early',
  },
];
const MEDIA_DA_CONTA = 101.74;

// Quem chegou pelos anúncios: a base das listas do caminho do dinheiro e das propostas do anúncio.
const PESSOAS = [
  {
    conversation_id: 9001,
    card_id: 501,
    title: 'Mariana Souza',
    ad_name: 'Promoção de verão',
    stage_name: 'Orçamento enviado',
    status: 'open',
    value: 680,
    waiting_since: horasAtras(52),
    stalled: true,
    response_seconds: 180,
    answered: true,
  },
  {
    conversation_id: 9002,
    card_id: 502,
    title: 'Carlos Lima',
    ad_name: 'Promoção de verão',
    stage_name: 'Venda fechada',
    status: 'won',
    value: 1250,
    waiting_since: null,
    stalled: false,
    response_seconds: 95,
    answered: true,
  },
  {
    conversation_id: 9003,
    card_id: 503,
    title: 'Patrícia Gomes',
    ad_name: 'Promoção de verão',
    stage_name: 'Orçamento enviado',
    status: 'open',
    value: 420,
    waiting_since: horasAtras(76),
    stalled: true,
    response_seconds: 1260,
    answered: true,
  },
  {
    conversation_id: 9004,
    card_id: 504,
    title: 'Rafael Dias',
    ad_name: 'Promoção de verão',
    stage_name: 'Venda fechada',
    status: 'won',
    value: 890,
    waiting_since: null,
    stalled: false,
    response_seconds: 240,
    answered: true,
  },
  {
    conversation_id: 9005,
    card_id: 505,
    title: 'Juliana Rocha',
    ad_name: 'Coleção nova',
    stage_name: 'Novo contato',
    status: 'open',
    value: null,
    waiting_since: horasAtras(5),
    stalled: false,
    response_seconds: null,
    answered: false,
  },
  {
    conversation_id: 9006,
    card_id: null,
    title: 'Bruno Alves',
    ad_name: 'Coleção nova',
    stage_name: null,
    status: null,
    value: null,
    waiting_since: null,
    stalled: false,
    response_seconds: 900,
    answered: true,
  },
];

const paraLista = pessoa => ({ ...pessoa, touched_at: horasAtras(30) });

const conselho = () => {
  const paradas = PESSOAS.filter(pessoa => pessoa.stalled);
  return {
    run_id: 900,
    local_date: hoje(),
    rules_version: 'f5.1',
    writer: { status: 'rule', reason: null },
    actions: [
      {
        id: 31,
        position: 1,
        kind: 'stalled_quotes',
        variant: null,
        status: 'open',
        opened: false,
        ad_id: AD_ATIVO,
        ad_name: 'Promoção de verão',
        facts: {
          count: paradas.length,
          value: paradas.reduce((soma, pessoa) => soma + pessoa.value, 0),
          days: 2,
          ad_name: 'Promoção de verão',
        },
        button: { target: 'stalled_list', step: null, url: null },
        source: 'rule',
        headline: null,
        body: null,
        why: null,
        cards: paradas.map(pessoa => ({
          id: pessoa.card_id,
          title: pessoa.title,
          value: pessoa.value,
          conversation_id: pessoa.conversation_id,
          waiting_since: pessoa.waiting_since,
        })),
      },
    ],
  };
};

const periodo = chave => {
  const days = DIAS[chave] || 30;
  return {
    period: chave || '30d',
    days,
    from: dia(diasAtras(days - 1)),
    to: hoje(),
    open: true,
  };
};

const painel = chave => ({
  ...periodo(chave),
  currency: 'BRL',
  source: 'meta',
  synced_at: new Date().toISOString(),
  refreshing: false,
  totals: {
    spend: 508.7,
    conversations: 57,
    quotes: 14,
    open_quotes: 9,
    sales: 5,
    sales_value: 3890,
    cost_per_conversation: 8.92,
    cost_per_sale: MEDIA_DA_CONTA,
    return_per_real: 7.65,
    other_spend: 0,
  },
  ads: ANUNCIOS,
  other_ads: [],
  advice: conselho(),
  response_time: {
    days: DIAS[chave] || 30,
    median_seconds: 240,
    answered: 52,
    unanswered: 2,
    slow: 6,
    target_seconds: 300,
  },
  meta_comparison: null,
  confidence: {
    window_days: 30,
    conversations: 57,
    ad: 50,
    ad_name: 5,
    campaign: 2,
    unknown: 0,
  },
});

const LISTAS = {
  conversations: () => PESSOAS,
  quotes: () => PESSOAS.filter(pessoa => pessoa.card_id && pessoa.value),
  sales: () => PESSOAS.filter(pessoa => pessoa.status === 'won'),
  slow_replies: () =>
    PESSOAS.filter(pessoa => !pessoa.answered || pessoa.response_seconds > 300),
};

const listaDoCaminho = (step, chave) => {
  const itens = (LISTAS[step] || LISTAS.conversations)().map(paraLista);
  return {
    step,
    period: chave || '30d',
    days: DIAS[chave] || 30,
    total: itens.length,
    items: itens,
  };
};

// Um dia de gasto e conversas, com um desenho que sobe e desce (sempre o mesmo, a demo não muda ao recarregar).
const diario = (days, escala) =>
  Array.from({ length: days }, (_, index) => ({
    date: dia(diasAtras(days - 1 - index)),
    spend: Number((escala * (10 + ((index * 7) % 9))).toFixed(2)),
    conversations: (index * 5) % 4,
  }));

const DETALHES = {
  [AD_ATIVO]: {
    campaign_name: 'Verão 2026',
    adset_name: 'Região da loja, 25 a 55 anos',
    reason: {
      kind: 'below_average',
      missing_conversations: null,
      difference: 19.28,
    },
    escala: 1,
  },
  [AD_PAUSADO]: {
    campaign_name: 'Coleção nova',
    adset_name: 'Região da loja, 18 a 45 anos',
    reason: { kind: 'early', missing_conversations: 11, difference: null },
    escala: 0.3,
  },
};

// "Sem números": o anúncio acabou de entrar e o banco ainda não tem nada dele, então volta `{ ad: null }`.
const anuncioPorDentro = (adId, chave) => {
  const linha = ANUNCIOS.find(item => item.ad_id === adId);
  const detalhe = DETALHES[adId];
  if (!linha || !detalhe) return null;
  const { escala, ...resto } = detalhe;
  const tempo = periodo(chave);
  return {
    ...tempo,
    ...linha,
    ...resto,
    currency: 'BRL',
    preview_url: null,
    account_average_cost_per_sale: MEDIA_DA_CONTA,
    daily: diario(tempo.days, escala),
    people: [],
    quotes_list: PESSOAS.filter(
      pessoa => pessoa.ad_name === linha.name && pessoa.card_id
    ).map(pessoa => ({
      card_id: pessoa.card_id,
      title: pessoa.title,
      value: pessoa.value,
      status: pessoa.status,
      stage_name: pessoa.stage_name,
      conversation_id: pessoa.conversation_id,
      waiting_since: pessoa.waiting_since,
    })),
  };
};

// ---------- Dados que as ações mudam ----------

const orcamento = (adId, nome, ativos) => ({
  level: 'adset',
  object_id: `${adId}9`,
  object_name: nome,
  kind: 'daily',
  amount: '20.00',
  currency: 'BRL',
  start_time: `${dia(diasAtras(20))}T00:00:00-0300`,
  end_time: null,
  started: true,
  ads_count: 1,
  active_ads_count: ativos,
  min_daily: 6,
  max_daily: 500,
  can_change: true,
  adset_id: `${adId}9`,
  today: hoje(),
});

const comentario = (id, autor, texto, horas, extra = {}) => ({
  id,
  author: autor,
  text: texto,
  created_time: horasAtras(horas),
  hidden: false,
  can_reply: true,
  can_hide: true,
  can_delete: true,
  can_reply_private: false,
  private_reply_expired: false,
  private_reply: null,
  replies: [],
  ...extra,
});

const pessoaFb = name => ({ name, is_page: false });
const paginaFb = { name: PAGINA.name, is_page: true };
const pessoaIg = username => ({ name: null, username, is_page: false });
const paginaIg = {
  name: INSTAGRAM.name,
  username: INSTAGRAM.username,
  is_page: true,
};

const dadosIniciais = () => ({
  situacao: {
    [AD_ATIVO]: 'ACTIVE',
    [AD_PAUSADO]: 'PAUSED',
    [AD_SEM_NUMEROS]: 'ACTIVE',
  },
  orcamentos: {
    [AD_ATIVO]: orcamento(AD_ATIVO, 'Região da loja, 25 a 55 anos', 1),
    [AD_PAUSADO]: orcamento(AD_PAUSADO, 'Região da loja, 18 a 45 anos', 0),
    [AD_SEM_NUMEROS]: orcamento(AD_SEM_NUMEROS, 'Vídeo da loja', 1),
  },
  pausados: [
    {
      ad_id: AD_PAUSADO,
      name: 'Coleção nova',
      created_at: horasAtras(120),
      budget: { kind: 'daily', amount: 20, currency: 'BRL' },
    },
  ],
  facebook: {
    [AD_ATIVO]: [
      comentario(
        'fb_1',
        pessoaFb('Ana Ribeiro'),
        'Vocês entregam no meu bairro?',
        6,
        {
          replies: [
            comentario(
              'fb_1_r',
              paginaFb,
              'Entregamos sim, Ana! Chama a gente no WhatsApp que passamos o prazo.',
              5
            ),
          ],
        }
      ),
      comentario(
        'fb_2',
        pessoaFb('Pedro Martins'),
        'Compre seguidores baratos, chama no privado!!!',
        20,
        { hidden: true }
      ),
      comentario(
        'fb_3',
        pessoaFb('Luiza Fernandes'),
        'Qual o valor do kit da foto?',
        2
      ),
    ],
  },
  instagram: {
    [AD_ATIVO]: [
      comentario(
        'ig_1',
        pessoaIg('camila.store'),
        'Ainda tem no tamanho M?',
        3,
        { can_reply_private: true }
      ),
      comentario('ig_2', pessoaIg('joao_p'), 'Amei! 😍', 9, {
        can_reply_private: true,
      }),
    ],
  },
  formularios: [
    {
      id: '9001',
      name: 'Peça seu orçamento',
      status: 'ACTIVE',
      leads_count: 4,
      past_count: 0,
      last_lead_at: horasAtras(3),
      brought: null,
      destination: {
        pipeline_id: 1,
        pipeline_name: 'Vendas',
        stage_id: 11,
        stage_name: 'Novo contato',
      },
    },
    {
      id: '9002',
      name: 'Cadastro para novidades',
      status: 'ACTIVE',
      leads_count: 0,
      past_count: 7,
      last_lead_at: null,
      brought: null,
      destination: null,
    },
  ],
  recebendo: true,
  relatorio: {
    enabled: true,
    alert_enabled: false,
    inbox_id: 1,
    phone: '+5511900000002',
    last_summary_at: horasAtras(14),
    last_alert_at: null,
    last_error: null,
    last_error_at: null,
    origins: [
      {
        inbox_id: 1,
        name: 'Loja Exemplo',
        phone_number: WHATSAPP.phone,
        kind: 'whatsapp_cloud',
        templates: { summary: 'approved', alert: 'approved' },
      },
    ],
    template_texts: {
      summary: {
        name: 'chat2you_resumo_anuncios',
        body: 'Resumo de ontem: {{1}}',
      },
      alert: { name: 'chat2you_alerta_anuncio', body: 'Atenção: {{1}}' },
    },
    schedule: {
      summary_local_time: '08:00',
      alert_local_time: '16:30',
      time_zone: 'America/Sao_Paulo',
    },
  },
  enviados: 0,
});

const LEADS = [
  ['Mariana Souza', '+5511900000101', 1],
  ['Carlos Lima', '+5511900000102', 5],
  ['Patrícia Gomes', '+5511900000103', 26],
  ['Rafael Dias', '+5511900000104', 50],
].map(([name, phone, horas], index) => ({
  id: index + 1,
  card_id: 601 + index,
  name,
  phone,
  email: null,
  form_name: 'Peça seu orçamento',
  ad_name: 'Promoção de verão',
  pipeline_id: 1,
  pipeline_name: 'Vendas',
  stage_name: 'Novo contato',
  received_at: horasAtras(horas),
  new_contact: index !== 2,
}));

// ---------- Rotas ----------

const corpo = config => {
  if (typeof config.data === 'string') return JSON.parse(config.data || '{}');
  return config.data || {};
};

const segmentos = (caminho, marca) =>
  caminho.split(marca)[1].split('/').filter(Boolean).map(decodeURIComponent);

const mudarComentarios = (lista, id, mudar) =>
  lista
    .filter(item => !(mudar === null && item.id === id))
    .map(item => {
      if (item.id === id && mudar) return mudar(item);
      return { ...item, replies: mudarComentarios(item.replies, id, mudar) };
    });

const achar = (lista, id) =>
  lista.reduce(
    (achado, item) =>
      achado || (item.id === id ? item : achar(item.replies, id)),
    null
  );

const criarRotas = ctx => {
  const atual = () => ctx.estado.value;
  const mudarEstado = parte => {
    ctx.estado.value = { ...ctx.estado.value, ...parte };
    return ok(payloadConexao(ctx.estado.value));
  };
  const mudarDados = parte => {
    ctx.dados = { ...ctx.dados, ...parte };
  };

  const funis = () => {
    const ligado = Boolean(atual().salesSignal);
    return {
      funnels: [
        {
          id: 1,
          name: 'Vendas',
          numbers: [{ inbox_id: 1, name: WHATSAPP.name }],
          enabled: ligado,
          stages: [
            { id: 11, name: 'Novo contato', funnel_stage_type: 'lead' },
            {
              id: 12,
              name: 'Orçamento enviado',
              funnel_stage_type: ligado ? 'opportunity' : null,
            },
            { id: 13, name: 'Venda fechada', funnel_stage_type: null },
          ].map(stage => ({ ...stage, result: stage.id === 13 })),
          missing: ligado ? [] : ['stages'],
        },
      ],
      unlinked_numbers: [],
      ai_available: false,
    };
  };

  const opcoes = () => ({
    needs_login: false,
    facebook_login: {
      app_id: 'demo',
      configuration_id: 'demo',
      api_version: 'v22.0',
    },
    kinds: ['ad'],
    pages: [PAGINA],
    instagram: {
      id: INSTAGRAM.id,
      username: INSTAGRAM.username,
      posts: [],
      publish_left: null,
    },
    whatsapp_numbers: [WHATSAPP],
    posts: [],
    images: [
      ['#0f766e', 'Verão'],
      ['#7c3aed', 'Coleção'],
      ['#b45309', 'Kit'],
      ['#be123c', 'Oferta'],
    ].map(([cor, texto], index) => ({
      hash: `demo_img_${index + 1}`,
      url: imagem(cor, texto),
      width: 600,
      height: 600,
    })),
    currency: 'BRL',
    today: hoje(),
    time_zone: 'America/Sao_Paulo',
    min_daily: 6,
    max_daily: 500,
    destinations: ['WHATSAPP', 'WEBSITE'],
    placements_by_destination: {
      WHATSAPP: ['AUTO'],
      WEBSITE: ['AUTO', 'INSTAGRAM', 'FACEBOOK'],
    },
  });

  const gestao = adId => {
    const status = ctx.dados.situacao[adId];
    if (!status) return falha(404, 'ad_not_found');
    return ok({
      management: {
        status,
        effective_status: status,
        mode: 'facebook_login',
        can_change: true,
        needs_login: false,
        post: {
          message: 'Promoção de verão na Loja Exemplo: até 30% off.',
          created_time: horasAtras(240),
          permalink_url: null,
          page_name: PAGINA.name,
          reactions: 87,
          comments: 3,
          shares: 4,
        },
      },
    });
  };

  const mudarSituacao = (adId, status) => {
    const orcamentoAtual = ctx.dados.orcamentos[adId];
    mudarDados({
      situacao: { ...ctx.dados.situacao, [adId]: status },
      orcamentos: {
        ...ctx.dados.orcamentos,
        [adId]: {
          ...orcamentoAtual,
          active_ads_count: status === 'ACTIVE' ? 1 : 0,
        },
      },
      pausados:
        status === 'ACTIVE'
          ? ctx.dados.pausados.filter(item => item.ad_id !== adId)
          : ctx.dados.pausados,
    });
    return ok({ status, held_by: null });
  };

  const criarAnuncio = rascunho => {
    const budget = {
      ...orcamento(AD_NOVO, rascunho.name || 'Anúncio novo', 0),
      amount: Number(rascunho.daily_amount || 20),
      start_time: rascunho.start_date || hoje(),
      end_time: rascunho.end_date || null,
    };
    const novo = {
      ad_id: AD_NOVO,
      name: rascunho.name || 'Anúncio novo',
      status: 'PAUSED',
      budget,
    };
    mudarDados({
      situacao: { ...ctx.dados.situacao, [AD_NOVO]: 'PAUSED' },
      orcamentos: { ...ctx.dados.orcamentos, [AD_NOVO]: budget },
      pausados: [
        { ...novo, created_at: new Date().toISOString() },
        ...ctx.dados.pausados.filter(item => item.ad_id !== AD_NOVO),
      ],
    });
    return ok(novo);
  };

  const novoOrcamento = (adId, pedido) => {
    const antes = ctx.dados.orcamentos[adId];
    if (!antes) return falha(404, 'budget_not_found');
    const depois = {
      ...antes,
      amount: Number(pedido.amount).toFixed(2),
      end_time: pedido.end_time || null,
    };
    mudarDados({ orcamentos: { ...ctx.dados.orcamentos, [adId]: depois } });
    return ok({ budget: depois });
  };

  // Facebook e Instagram: a mesma lista guardada por anúncio, com as ações que a tela relê em seguida.
  const comentarios = (rede, adId) => ctx.dados[rede][adId] || [];
  const gravar = (rede, adId, lista) =>
    mudarDados({ [rede]: { ...ctx.dados[rede], [adId]: lista } });

  const listarComentarios = (rede, adId) => {
    const lista = comentarios(rede, adId);
    const base = {
      status: 'ready',
      permalink_url: null,
      comments: lista,
      total: lista.length,
      next_cursor: null,
    };
    if (rede === 'facebook') return ok({ comments: base });
    return ok({
      ...base,
      account: { username: INSTAGRAM.username, name: INSTAGRAM.name },
      inbox_id: 1,
    });
  };

  const responderComentario = (rede, adId, id, texto) => {
    const lista = comentarios(rede, adId);
    if (!achar(lista, id)) return falha(404, 'comment_not_found');
    if (!String(texto || '').trim()) return falha(422, 'invalid_text');
    const resposta = comentario(
      `${id}_r${Date.now()}`,
      rede === 'facebook' ? paginaFb : paginaIg,
      texto,
      0
    );
    gravar(
      rede,
      adId,
      mudarComentarios(lista, id, item => ({
        ...item,
        replies: [...item.replies, resposta],
      }))
    );
    return ok({ id: resposta.id });
  };

  const ocultarComentario = (rede, adId, id, hidden) => {
    const lista = comentarios(rede, adId);
    if (!achar(lista, id)) return falha(404, 'comment_not_found');
    gravar(
      rede,
      adId,
      mudarComentarios(lista, id, item => ({ ...item, hidden }))
    );
    return ok({ hidden });
  };

  const apagarComentario = (rede, adId, id) => {
    const lista = comentarios(rede, adId);
    if (!achar(lista, id)) return falha(404, 'comment_not_found');
    gravar(rede, adId, mudarComentarios(lista, id, null));
    return ok({ deleted: true });
  };

  const privado = (adId, id, enviar) => {
    const lista = comentarios('instagram', adId);
    if (!achar(lista, id)) return falha(404, 'comment_not_found');
    const sentAt = new Date().toISOString();
    gravar(
      'instagram',
      adId,
      mudarComentarios(lista, id, item => ({
        ...item,
        can_reply_private: !enviar,
        private_reply: enviar
          ? {
              sent_at: sentAt,
              conversation_path: null,
              confirmed: true,
              can_release: false,
            }
          : null,
      }))
    );
    return ok(enviar ? { sent_at: sentAt, conversation_path: null } : {});
  };

  const facebookComentarios = (method, adId, resto, dados) => {
    const [id, acao] = resto;
    if (!id && method === 'get') return listarComentarios('facebook', adId);
    if (acao === 'reply')
      return responderComentario('facebook', adId, id, dados.content);
    if (method === 'patch')
      return ocultarComentario('facebook', adId, id, Boolean(dados.hidden));
    if (method === 'delete') return apagarComentario('facebook', adId, id);
    return null;
  };

  const instagramComentarios = (method, adId, resto, dados) => {
    const [id, acao, sub] = resto;
    if (!id && method === 'get') return listarComentarios('instagram', adId);
    if (method === 'delete') return apagarComentario('instagram', adId, id);
    if (acao === 'reply')
      return responderComentario('instagram', adId, id, dados.content);
    if (acao === 'hide')
      return ocultarComentario('instagram', adId, id, Boolean(dados.hidden));
    if (acao === 'private_reply') return privado(adId, id, sub !== 'release');
    return null;
  };

  const anuncio = (method, [adId, parte, ...resto], dados) => {
    if (parte === 'management') return gestao(adId);
    if (parte === 'status') return mudarSituacao(adId, dados.status);
    if (parte === 'budget' && method === 'get') {
      const budget = ctx.dados.orcamentos[adId];
      return budget ? ok({ budget }) : falha(404, 'budget_not_found');
    }
    if (parte === 'budget') return novoOrcamento(adId, dados);
    if (parte === 'facebook_comments')
      return facebookComentarios(method, adId, resto, dados);
    if (parte === 'instagram_comments')
      return instagramComentarios(method, adId, resto, dados);
    return null;
  };

  const relatorio = (method, resto, dados) => {
    if (resto[0] === 'test') {
      mudarDados({ enviados: ctx.dados.enviados + 1 });
      if (ctx.dados.enviados > 3) return falha(429, 'rate_limited');
      return ok({ sent: true, sent_at: new Date().toISOString() });
    }
    if (method === 'patch') {
      mudarDados({
        relatorio: { ...ctx.dados.relatorio, ...dados.whatsapp_report },
      });
    }
    return ok({ whatsapp_report: ctx.dados.relatorio });
  };

  // Rotas de uma palavra só, por método e nome.
  const simples = {
    'get panel': params => ok({ panel: painel(params.period) }),
    'get panel_ad': params =>
      ok({ ad: anuncioPorDentro(params.ad_id, params.period) }),
    'get panel_list': params =>
      ok({ list: listaDoCaminho(params.step, params.period) }),
    'post insights': () =>
      ok({
        insights: {
          synced_at: new Date().toISOString(),
          refreshing: false,
          backfilling: false,
          today: hoje(),
          date: hoje(),
          spend: 18.4,
          currency: 'BRL',
          conversations: 3,
          ad_conversations_today: 3,
        },
      }),
    'post daily_action': () => ok({ daily_action: null }),
    'post quote_message': (_params, dados) =>
      ok({
        quote_message: {
          card_id: dados.card_id,
          conversation_id: null,
          applies: true,
          reason: null,
          message:
            'Oi! Passando para saber se ficou alguma dúvida sobre o orçamento. Posso separar o pedido para você?',
          source_quote: null,
        },
      }),
    'post suggest_stages': () => ok({ suggestions: [] }),
    'get funnels': () => ok(funis()),
    'patch funnel': (_params, dados) => {
      mudarEstado({ salesSignal: dados.enabled !== false });
      return ok(funis());
    },
    'get ad_accounts': () => ok({ ad_accounts: AD_ACCOUNTS }),
    'get pixels': () => ok({ pixels: PIXELS }),
    'post selection': (_params, dados) => {
      const conta =
        AD_ACCOUNTS.find(item => item.id === dados.ad_account_id) ||
        AD_ACCOUNTS[0];
      return mudarEstado({ adAccount: { id: conta.id, name: conta.name } });
    },
    'patch destinations': (_params, dados) =>
      mudarEstado({ destinations: dados.destinations }),
    'post facebook_login': () => mudarEstado({ facebook: true }),
    'get pages': () => ok({ pages: [PAGINA] }),
    // Cena "sem-conta": o login refeito na criação limpou a conta de anúncios (o defeito de 28/10).
    'get create_options': () => {
      if (atual().perdeContaNaCriacao) {
        ctx.estado.value = {
          ...atual(),
          perdeContaNaCriacao: false,
          adAccount: null,
        };
      }
      if (!atual().adAccount) return falha(404, 'not_connected');
      return ok({ options: opcoes() });
    },
    'post media': () =>
      ok({
        media: {
          kind: 'image',
          hash: `demo_up_${Date.now()}`,
          url: imagem('#1d4ed8', 'Sua foto'),
          width: 1080,
          height: 1080,
        },
      }),
    'post ads': (_params, dados) => criarAnuncio(dados),
    'get paused_ads': () => ok({ ads: ctx.dados.pausados }),
  };

  const rotaConexao = (method, segs, params, dados) => {
    if (!segs.length) {
      if (method === 'get') return ok(payloadConexao(atual()));
      if (method === 'delete')
        return mudarEstado({ facebook: false, adAccount: null });
      if (method === 'put') return mudarEstado({ facebook: true });
      return null;
    }
    const [primeiro, ...resto] = segs;
    if (primeiro === 'ads' && resto.length)
      return anuncio(method, resto, dados);
    if (primeiro === 'whatsapp_report') return relatorio(method, resto, dados);
    if (primeiro === 'advisor_actions') return ok({});
    const handler = simples[`${method} ${primeiro}`];
    return handler ? handler(params, dados) : null;
  };

  const payloadFormularios = () => ({
    pages: [
      {
        ...PAGINA,
        receiving: ctx.dados.recebendo,
        forms: ctx.dados.formularios,
      },
    ],
    pipelines: PIPELINES,
    recent_leads: LEADS,
  });

  const destino = dados => {
    const pipeline =
      PIPELINES.find(item => item.id === Number(dados.pipeline_id)) ||
      PIPELINES[0];
    const stage =
      pipeline.stages.find(item => item.id === Number(dados.stage_id)) ||
      pipeline.stages[0];
    return {
      pipeline_id: pipeline.id,
      pipeline_name: pipeline.name,
      stage_id: stage.id,
      stage_name: stage.name,
    };
  };

  const mudarFormulario = (formId, mudar) =>
    mudarDados({
      formularios: ctx.dados.formularios.map(form =>
        form.id === formId ? mudar(form) : form
      ),
    });

  const rotaFormularios = (method, segs, dados) => {
    const [tipo, id, acao] = segs;
    if (!segs.length && method === 'get') return ok(payloadFormularios());
    if (tipo === 'pages') {
      mudarDados({ recebendo: method === 'post' });
      return ok(payloadFormularios());
    }
    const form = ctx.dados.formularios.find(item => item.id === id);
    if (tipo !== 'forms' || !form) return falha(404, 'form_not_found');
    if (acao === 'destination' && method === 'delete') {
      mudarFormulario(id, item => ({ ...item, destination: null }));
      return { status: 204, data: '' };
    }
    const escolhido = destino(dados);
    if (acao === 'destination') {
      const imported = dados.import_past ? form.past_count : 0;
      mudarFormulario(id, item => ({ ...item, destination: escolhido }));
      return ok({ destination: escolhido, imported, importing: imported > 0 });
    }
    if (acao === 'bring_past') {
      const brought = {
        count: form.past_count,
        pipeline_name: escolhido.pipeline_name,
        stage_name: escolhido.stage_name,
      };
      mudarFormulario(id, item => ({ ...item, brought }));
      return ok({ imported: form.past_count, ...brought });
    }
    return null;
  };

  return config => {
    const caminho = String(config.url || '').split('?')[0];
    const method = String(config.method || 'get').toLowerCase();
    const params = config.params || {};
    if (caminho.endsWith(LINKS)) return ok({ payload: [] });
    if (caminho.includes(FORMULARIOS))
      return rotaFormularios(
        method,
        segmentos(caminho, FORMULARIOS),
        corpo(config)
      );
    if (caminho.includes(CONEXAO))
      return rotaConexao(
        method,
        segmentos(caminho, CONEXAO),
        params,
        corpo(config)
      );
    return null;
  };
};

// Instala uma vez por página; chamada de novo, só passa a usar o estado novo.
export const instalarMetaDemo = estado => {
  if (window[GLOBAL]) {
    window[GLOBAL].estado = estado;
    return;
  }
  const ctx = { estado, dados: dadosIniciais() };
  window[GLOBAL] = ctx;
  const responder = criarRotas(ctx);

  window.axios.interceptors.request.use(config => {
    const resposta = responder(config);
    if (!resposta) return config;
    return {
      ...config,
      adapter: async cfg => {
        await esperar();
        if (resposta.status >= 400) {
          throw Object.assign(new Error(resposta.data.error), {
            config: cfg,
            response: { status: resposta.status, data: resposta.data },
          });
        }
        return {
          data: resposta.data,
          status: resposta.status,
          statusText: 'OK',
          headers: {},
          config: cfg,
        };
      },
    };
  });
};
