// Página inicial de Configurações (#1617): um cartão por assunto, cada coisa num lugar só.
//
// `origem` é o `name` do item que o Sidebar.vue já monta (com as flags e permissões aplicadas). O cartão só
// aparece quando esse item existe para a pessoa e a rota dele abre (mesma checagem do menu). Assim a página não
// repete regra de quem vê o quê: herda do menu de sempre.
//
// `passo` liga o cartão à trilha de Primeiros passos (config/onboarding/trilha.yml): passo pendente vira
// "Falta: …" no cartão; feito vira "Pronto". `contagem` diz qual número barato (já na store) mostrar.
//
// O que saiu daqui por redundância (decisão do Rodrigo, 15/10): Prospecção (fica em Prospecção ›
// Configurações), Modelos (Campanhas › Modelos WhatsApp) e Cobrança (coberta por Plano e faturas).
export const SAIRAM_DAS_CONFIGURACOES = [
  'Settings Prospecting',
  'Settings Templates',
  'Settings Billing',
];

export const GRUPOS_DE_CARTOES = [
  {
    id: 'SUA_EMPRESA',
    cartoes: [
      {
        id: 'DADOS_EMPRESA',
        origem: 'Settings Account Settings',
        icone: 'i-lucide-building-2',
      },
      {
        id: 'PLANO',
        origem: 'Financial',
        icone: 'i-lucide-receipt',
      },
      // Hoje o horário mora em dois lugares (cada canal e o calendário dos Prazos de resposta). Não unificamos
      // o dado agora: o cartão leva ao lugar atual e diz isso. Pendência registrada na Issue #1617.
      {
        id: 'HORARIOS',
        origem: 'Settings Inboxes',
        icone: 'i-lucide-clock',
        nota: 'HORARIOS',
      },
    ],
  },
  {
    id: 'CANAIS',
    cartoes: [
      {
        id: 'CANAIS',
        origem: 'Settings Inboxes',
        icone: 'i-lucide-message-circle',
        passo: 'canal',
        contagem: 'caixas',
      },
    ],
  },
  {
    id: 'PESSOAS',
    cartoes: [
      {
        id: 'USUARIOS',
        origem: 'Settings Agents',
        icone: 'i-lucide-square-user',
        passo: 'equipe',
        contagem: 'usuarios',
      },
      {
        id: 'TIMES',
        origem: 'Settings Teams',
        icone: 'i-lucide-users',
        contagem: 'times',
      },
      // Atribuição é a dona de política, capacidade e passagem do CRM para quem administra.
      {
        id: 'ATRIBUICAO',
        origem: 'Settings Agent Assignment',
        icone: 'i-lucide-user-cog',
      },
      // Quem não administra, mas cuida da IA do CRM, chega na passagem direto por este cartão.
      {
        id: 'PASSAGEM',
        origem: 'Settings CRM Handoff',
        icone: 'i-lucide-hand-helping',
      },
      {
        id: 'FUNCOES',
        origem: 'Settings Custom Roles',
        icone: 'i-lucide-shield-plus',
      },
    ],
  },
  {
    id: 'ATENDIMENTO',
    cartoes: [
      {
        id: 'RESPOSTAS',
        origem: 'Settings Canned Responses',
        icone: 'i-lucide-message-square-quote',
      },
      {
        id: 'ETIQUETAS',
        origem: 'Settings Labels',
        icone: 'i-lucide-tags',
        passo: 'configuracoes',
        contagem: 'etiquetas',
      },
      {
        id: 'ENCERRAR',
        origem: 'Conversation Workflow',
        icone: 'i-lucide-circle-check-big',
      },
      {
        id: 'ACOES',
        origem: 'Settings Macros',
        icone: 'i-lucide-mouse-pointer-click',
      },
      // Só quando Relacionamentos está desligado: com ele ligado, os campos moram lá (o Sidebar já tira).
      {
        id: 'CAMPOS',
        origem: 'Settings Custom Attributes',
        icone: 'i-lucide-list-plus',
      },
    ],
  },
  {
    id: 'CONEXOES',
    cartoes: [
      {
        id: 'INTEGRACOES',
        origem: 'Settings Integrations',
        icone: 'i-lucide-blocks',
        passo: 'chave_ia',
      },
      {
        id: 'ROBOS',
        origem: 'Settings Agent Bots',
        icone: 'i-lucide-bot',
      },
      {
        id: 'IMPORTAR',
        origem: 'Settings Data',
        icone: 'i-lucide-database',
      },
    ],
  },
  {
    id: 'SEGURANCA',
    cartoes: [
      {
        id: 'LOGIN',
        origem: 'Settings Security',
        icone: 'i-lucide-key-round',
      },
      {
        id: 'HISTORICO',
        origem: 'Settings Audit Logs',
        icone: 'i-lucide-history',
      },
    ],
  },
];

export const ORIGENS_DOS_CARTOES = [
  ...new Set(
    GRUPOS_DE_CARTOES.flatMap(grupo =>
      grupo.cartoes.map(cartao => cartao.origem)
    )
  ),
];
