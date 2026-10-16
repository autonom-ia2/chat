// Página inicial de Configurações (#1617): um cartão por assunto, cada coisa num lugar só.
//
// `origem` é o `name` do item que o Sidebar.vue já monta (com as flags e permissões aplicadas). O cartão só
// aparece quando esse item existe para a pessoa e a rota dele abre (mesma checagem do menu). Assim a página não
// repete regra de quem vê o quê: herda do menu de sempre.
//
// `rota` (sem `origem`): cartão de uma tela que não está em Configurações hoje; aparece se a rota abre para a
// pessoa (permissão e flag da própria rota) e se a instalação tem o recurso (`exige`).
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
      // Fica junto do Plano: é uma decisão de gasto do dono (a Meta cobra pelos modelos), não um ajuste do canal.
      {
        id: 'CUSTOS_WHATSAPP',
        rota: 'modelos_whatsapp_autorizacao',
        icone: 'i-lucide-badge-dollar-sign',
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
        // Caixa que pede para reconectar (o mesmo dado do aviso vermelho no menu de sempre) vira selo vermelho.
        saude: true,
      },
      {
        id: 'EMAIL_ENVIO',
        rota: 'campaigns_email_sender_index',
        exige: 'campanhasPorEmail',
        icone: 'i-lucide-mail',
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
      {
        id: 'QUEM_CUIDA',
        rota: 'crm_caixas',
        exige: 'crm',
        icone: 'i-lucide-network',
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
        // #1660: com a aba "Agente de IA" por caixa (#1648) os agentes de outro sistema vivem em Agentes.
        exige: 'semAgenteIaPorCaixa',
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
      grupo.cartoes.map(cartao => cartao.origem).filter(Boolean)
    )
  ),
];
