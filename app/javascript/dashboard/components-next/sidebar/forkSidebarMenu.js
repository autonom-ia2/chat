// Menu lateral novo (#1617, Proposta A). Camada do fork, ADITIVA: o Sidebar.vue continua montando a lista de
// sempre, com as flags e as permissões já aplicadas, e esta função só reorganiza o que chega. Cada item é achado
// pelo `name`; o layout abaixo diz em que grupo ele mora, em que ordem e com que nome.
//
// Regras que não quebram:
// - Item do Chatwoot que o layout não conhece vai para "Outros" — nunca some do menu.
// - Item que o layout pede e não chegou (flag desligada, sem permissão) simplesmente não aparece.
// - Rotas não mudam: o item leva para o mesmo lugar de antes.
//
// O teste `forkSidebarMenu.spec.js` monta o Sidebar.vue com as flags ligadas e falha quando um `name` novo do
// upstream não está mapeado aqui, ou quando um nome daqui deixou de existir lá.
import {
  ORIGENS_DOS_CARTOES,
  SAIRAM_DAS_CONFIGURACOES,
} from 'dashboard/routes/dashboard/settings/inicio/cartoes';

// Importação de contatos mora em Relacionamentos (ou em Contatos, sem a navegação nova).
const IMPORTAR_CONTATOS = [
  'contacts_import_journey',
  'contacts_campaign_imports',
];

const ITEM = chave => `FORK_SIDEBAR.ITENS.${chave}`;

// `pega`: o item do topo, inteiro. `promove`: um filho vira item do topo. `monta`: item novo com filhos que
// vieram de outro lugar. `junta`: filhos de outro lugar que entram no fim de um item. Filho usado por
// `promove`, `monta` ou `junta` sai do lugar antigo.
export const FORK_LAYOUT = {
  topo: [
    // Só administra quem vê (o Sidebar já filtra). Some do topo quando a trilha termina.
    { pega: 'FirstSteps', someQuando: 'basicoConcluido' },
  ],
  grupos: [
    {
      id: 'ATENDER',
      itens: [
        {
          pega: 'Conversation',
          rotulosDosFilhos: { Participating: 'EM_QUE_PARTICIPO' },
        },
        { pega: 'Inbox', rotulo: 'NOTIFICACOES', icone: 'i-lucide-bell' },
        { pega: 'Calls' },
        {
          promove: 'CRM SLA',
          id: 'Prazos',
          rotulo: 'PRAZOS',
          icone: 'i-lucide-timer',
        },
      ],
    },
    {
      id: 'ACOMPANHAR',
      itens: [
        // A página Números (ex-Dashboard) virou aba do CRM: o item fica marcado nela.
        { pega: 'CRM', absorve: ['CRM Dashboard'] },
        // Prospecção mora junto do CRM (pedido do Rodrigo): achar a empresa e acompanhar a venda.
        { pega: 'Prospecting' },
        // Com a navegação de Relacionamentos ligada chega só ele; desligada, chegam Contatos e Empresas.
        {
          pega: 'Relationships',
          ativoPorPrefixo: ['relationships_'],
          ativoEm: IMPORTAR_CONTATOS,
        },
        { pega: 'Contacts', ativoEm: IMPORTAR_CONTATOS },
        { pega: 'Companies' },
        {
          monta: 'Agenda',
          rotulo: 'AGENDA',
          icone: 'i-lucide-calendar-days',
          filhos: [
            { de: 'CRM Booking' },
            { de: 'CRM Calendar' },
            { de: 'CRM My Booking Hours' },
            { de: 'CRM Booking Results', rotulo: 'MEUS_RESULTADOS' },
          ],
        },
      ],
    },
    {
      id: 'CRESCER',
      itens: [
        // Seus posts (#2302): acima de Campanhas, fora de Anúncios.
        { pega: 'SeusPosts' },
        {
          pega: 'Campaigns',
          // Telas filhas sem item próprio (editor de e-mail, nova campanha…) marcam Campanhas.
          ativoPorPrefixo: ['campaigns_'],
          rotulosDosFilhos: {
            'Campaign Journey': 'CAMPANHAS',
            'Campaign Management': 'VISAO_GERAL',
          },
        },
        // As duas abas da Cotação são da mesma tela: o item vira link direto.
        { pega: 'Insurance', direto: true },
      ],
    },
    {
      id: 'AUTOMATICO',
      itens: [{ pega: 'Agents', rotulo: 'AGENTES' }, { pega: 'Automacoes' }],
    },
    {
      id: 'RESULTADOS',
      itens: [
        {
          pega: 'Reports',
          rotulosDosFilhos: {
            'Reports Agent': 'RELATORIO_USUARIOS',
            'Reports Inbox': 'RELATORIO_CANAIS',
            'Reports Team': 'RELATORIO_TIMES',
            'Reports SLA': 'RELATORIO_PRAZOS',
          },
          junta: [{ de: 'CRM AI Usage', rotulo: 'GASTO_IA' }],
        },
      ],
    },
  ],
  rodape: [
    { pega: 'CentralDeAjuda', rotulo: 'AJUDA', icone: 'i-lucide-life-buoy' },
    // Abre a página de cartões; os filhos de Configurações viram cartões lá.
    {
      pega: 'Settings',
      rotulo: 'CONFIGURACOES',
      icone: 'i-lucide-settings',
      paginaInicial: 'settings_inicio',
    },
  ],
};

// Fora do menu de propósito (decisão do Rodrigo, 15/10). O Financeiro virou o cartão "Plano e faturas".
export const FORA_DO_MENU = ['Captain'];

// Filhos que a camada conhece, por pai que ela desmonta. Filho novo nestes pais sem lugar acende o teste.
export const FILHOS_CONHECIDOS = {
  CRM: [
    'CRM Kanban',
    'CRM Calendar',
    'CRM Scheduling',
    'CRM Dashboard',
    'CRM AI Usage',
    'CRM SLA',
  ],
  'CRM Scheduling': [
    'CRM Calendar',
    'CRM Booking',
    'CRM My Booking Hours',
    'CRM Booking Results',
  ],
  Insurance: ['Insurance Connections', 'Insurance Agent'],
  Financial: ['Subscription', 'Invoices'],
  Settings: [...ORIGENS_DOS_CARTOES, ...SAIRAM_DAS_CONFIGURACOES].filter(
    nome => nome !== 'Financial'
  ),
};

const todasAsEntradas = () => [
  ...FORK_LAYOUT.topo,
  ...FORK_LAYOUT.grupos.flatMap(grupo => grupo.itens),
  ...FORK_LAYOUT.rodape,
];

// Nomes do topo que o layout sabe tratar (com o que sai do menu e o que vira cartão).
export const nomesDoTopoConhecidos = () => [
  ...todasAsEntradas()
    .map(entrada => entrada.pega)
    .filter(Boolean),
  ...FORA_DO_MENU,
  ...ORIGENS_DOS_CARTOES.filter(nome => nome === 'Financial'),
];

// Todos os nomes que o layout cita, para o teste conferir que ainda existem no upstream.
export const nomesCitadosNoLayout = () => {
  const citados = todasAsEntradas().flatMap(entrada => [
    entrada.pega,
    entrada.promove,
    ...(entrada.filhos || []).map(filho => filho.de),
    ...(entrada.junta || []).map(filho => filho.de),
    ...(entrada.absorve || []),
    ...Object.keys(entrada.rotulosDosFilhos || {}),
  ]);
  return [...new Set(citados.filter(Boolean))];
};

const filhosUsados = () =>
  new Set(
    todasAsEntradas().flatMap(entrada => [
      entrada.promove,
      ...(entrada.filhos || []).map(filho => filho.de),
      ...(entrada.junta || []).map(filho => filho.de),
      ...(entrada.absorve || []),
    ])
  );

// Índice por `name`: itens do topo, filhos e netos (o subgrupo Agendamento do CRM). O primeiro que aparece vale.
const indexar = itens => {
  const indice = new Map();
  const fila = itens.map(item => ({ item, pai: null }));
  while (fila.length) {
    const { item, pai } = fila.shift();
    if (!indice.has(item.name)) indice.set(item.name, { item, pai });
    (item.children || []).forEach(filho =>
      fila.push({ item: filho, pai: item.name })
    );
  }
  return indice;
};

const reRotular = (item, rotulo, t) =>
  rotulo ? { ...item, label: t(ITEM(rotulo)) } : item;

// Tira do item os filhos que foram morar em outro lugar; subgrupo que fica vazio some.
const semFilhosUsados = (item, usados) => {
  if (!item.children) return item;
  const children = item.children
    .filter(filho => !usados.has(filho.name))
    .map(filho => semFilhosUsados(filho, usados))
    .filter(filho => !filho.children || filho.children.length > 0);
  return { ...item, children };
};

const juntarActiveOn = filhos => [
  ...new Set(
    filhos.flatMap(filho => [filho.to?.name, ...(filho.activeOn || [])])
  ),
];

// Item com um filho só (folha) vira link direto: o CRM só com o Kanban, a Agenda só com o Calendário.
const umFilhoViraLink = item => {
  if (!item.children || item.children.length !== 1) return item;
  const [unico] = item.children;
  if (unico.children || !unico.to) return item;
  const { children, ...resto } = item;
  return {
    ...resto,
    to: unico.to,
    activeOn: [
      ...new Set([...(item.activeOn || []), ...juntarActiveOn(children)]),
    ],
  };
};

const linkDireto = (item, conhecidos) => {
  const filhos = item.children || [];
  const todosConhecidos = filhos.every(filho =>
    conhecidos.includes(filho.name)
  );
  if (!filhos.length || !todosConhecidos) return item;
  const { children, ...resto } = item;
  return {
    ...resto,
    to: filhos[0].to,
    activeOn: [
      ...new Set([...(item.activeOn || []), ...juntarActiveOn(children)]),
    ],
  };
};

// Rotas a mais que marcam o item: no link direto entram no activeOn dele; no item com filhos, também no dele
// (acharAtivo olha o activeOn do pai quando nenhuma folha bate).
const comAtivoEm = (item, rotas) => ({
  ...item,
  activeOn: [...new Set([...(item.activeOn || []), ...rotas])],
});

const pegarFilhos = (lista, indice, t) =>
  lista
    .map(({ de, rotulo }) => {
      const achado = indice.get(de);
      return achado ? reRotular(achado.item, rotulo, t) : null;
    })
    .filter(Boolean);

const montarPega = (entrada, indice, usados, ctx) => {
  const achado = indice.get(entrada.pega);
  if (!achado || achado.pai) return null;
  const { t } = ctx;
  let item = semFilhosUsados(achado.item, usados);
  item = reRotular(item, entrada.rotulo, t);
  if (entrada.icone) item = { ...item, icon: entrada.icone };
  if (entrada.rotulosDosFilhos && item.children) {
    item = {
      ...item,
      children: item.children.map(filho =>
        reRotular(filho, entrada.rotulosDosFilhos[filho.name], t)
      ),
    };
  }
  if (entrada.junta) {
    const extras = pegarFilhos(entrada.junta, indice, t);
    item = { ...item, children: [...(item.children || []), ...extras] };
  }
  if (entrada.direto) {
    item = linkDireto(item, FILHOS_CONHECIDOS[entrada.pega] || []);
  }
  const absorvidos = (entrada.absorve || [])
    .map(nome => indice.get(nome)?.item)
    .filter(Boolean);
  const extrasDeAtivo = [
    ...juntarActiveOn(absorvidos),
    ...(entrada.ativoEm || []),
  ];
  if (extrasDeAtivo.length) item = comAtivoEm(item, extrasDeAtivo);
  if (entrada.ativoPorPrefixo) {
    item = { ...item, ativoPorPrefixo: entrada.ativoPorPrefixo };
  }
  return item;
};

const montarPromove = (entrada, indice, ctx) => {
  const achado = indice.get(entrada.promove);
  if (!achado) return null;
  return {
    ...achado.item,
    name: entrada.id,
    label: ctx.t(ITEM(entrada.rotulo)),
    icon: entrada.icone,
  };
};

const montarNovo = (entrada, indice, ctx) => {
  const children = pegarFilhos(entrada.filhos, indice, ctx.t);
  if (!children.length) return null;
  return umFilhoViraLink({
    name: entrada.monta,
    label: ctx.t(ITEM(entrada.rotulo)),
    icon: entrada.icone,
    activeOn: [],
    children,
  });
};

// Configurações leva à página de cartões e fica marcado em qualquer tela que virou cartão.
const montarConfiguracoes = (entrada, indice, ctx) => {
  const achado = indice.get(entrada.pega);
  if (!achado) return null;
  const financeiro = indice.get('Financial')?.item.children || [];
  const filhos = (achado.item.children || []).filter(
    filho => !SAIRAM_DAS_CONFIGURACOES.includes(filho.name)
  );
  return {
    name: achado.item.name,
    label: ctx.t(ITEM(entrada.rotulo)),
    icon: entrada.icone,
    to: ctx.accountScopedRoute(entrada.paginaInicial),
    activeOn: [
      entrada.paginaInicial,
      ...juntarActiveOn([...filhos, ...financeiro]),
    ],
  };
};

const montarEntrada = (entrada, indice, usados, ctx) => {
  if (entrada.someQuando && ctx[entrada.someQuando]) return null;
  if (entrada.paginaInicial) return montarConfiguracoes(entrada, indice, ctx);
  if (entrada.promove) return montarPromove(entrada, indice, ctx);
  if (entrada.monta) return montarNovo(entrada, indice, ctx);
  const item = montarPega(entrada, indice, usados, ctx);
  return item && umFilhoViraLink(item);
};

const montarLista = (entradas, indice, usados, ctx) =>
  entradas
    .map(entrada => montarEntrada(entrada, indice, usados, ctx))
    .filter(Boolean);

/**
 * Organiza a lista do Sidebar.vue no layout do fork.
 * @param {Array} upstreamItems o `menuItems` do Sidebar.vue
 * @param {{ t: Function, accountScopedRoute: Function, basicoConcluido?: boolean }} ctx
 * @returns {{ topo: Array, grupos: Array, rodape: Array, configuracoesExtras: Array }}
 */
export const organizeForkMenu = (upstreamItems, ctx) => {
  const indice = indexar(upstreamItems);
  const usados = filhosUsados();
  const conhecidos = new Set(nomesDoTopoConhecidos());

  const grupos = FORK_LAYOUT.grupos
    .map(grupo => ({
      id: grupo.id,
      label: ctx.t(`FORK_SIDEBAR.GRUPOS.${grupo.id}`),
      itens: montarLista(grupo.itens, indice, usados, ctx),
    }))
    .filter(grupo => grupo.itens.length);

  const outros = upstreamItems.filter(item => !conhecidos.has(item.name));
  if (outros.length) {
    grupos.push({
      id: 'OUTROS',
      label: ctx.t('FORK_SIDEBAR.GRUPOS.OUTROS'),
      itens: outros,
    });
  }

  // Filho de Configurações que ainda não tem cartão aparece na página, no grupo "Outros".
  const conhecidosDeConfiguracoes = FILHOS_CONHECIDOS.Settings;
  const configuracoesExtras = (
    indice.get('Settings')?.item.children || []
  ).filter(filho => !conhecidosDeConfiguracoes.includes(filho.name));

  return {
    topo: montarLista(FORK_LAYOUT.topo, indice, usados, ctx),
    grupos,
    rodape: montarLista(FORK_LAYOUT.rodape, indice, usados, ctx),
    configuracoesExtras,
  };
};

// Folhas navegáveis de um item: ele mesmo (link direto) ou filhos e netos com `to`.
export const folhasDe = item => {
  if (!item.children) return item.to ? [item] : [];
  return item.children.flatMap(filho => folhasDe(filho));
};

const parametrosBatem = (folha, rota) =>
  Object.keys(folha.to?.params || {}).every(
    chave => String(folha.to.params[chave]) === String(rota.params?.[chave])
  );

// Qual folha do menu inteiro está na tela, com a mesma ordem de critério do SidebarGroup do upstream:
// caminho igual, depois `activeOn` (com os parâmetros batendo), depois o começo do caminho.
export const acharAtivo = (itens, rota, resolverCaminho) => {
  const pares = itens.flatMap(item =>
    folhasDe(item).map(folha => ({ item, folha }))
  );
  const porCaminho = pares.find(
    ({ folha }) => resolverCaminho(folha.to) === rota.path
  );
  if (porCaminho) return porCaminho;
  const porNome = pares.filter(({ folha }) =>
    folha.activeOn?.includes(rota.name)
  );
  if (porNome.length) {
    return (
      porNome.find(({ folha }) => parametrosBatem(folha, rota)) || porNome[0]
    );
  }
  // Tela sem item próprio que pertence a um item (editor de e-mail das Campanhas, importação de contatos):
  // marca o item, sem marcar nenhum filho.
  const nomeDaRota = rota.name || '';
  const dono = itens.find(
    item =>
      item.activeOn?.includes(nomeDaRota) ||
      (item.ativoPorPrefixo || []).some(prefixo =>
        nomeDaRota.startsWith(prefixo)
      )
  );
  if (dono) return { item: dono, folha: dono.children ? null : dono };
  return (
    pares.find(({ folha }) =>
      rota.path.startsWith(`${resolverCaminho(folha.to)}/`)
    ) || null
  );
};
