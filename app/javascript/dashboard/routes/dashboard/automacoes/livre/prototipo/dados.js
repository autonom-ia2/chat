// #2414 F0 — adaptador falso do protótipo "Automação livre". Tudo aqui imita o
// que o motor novo vai devolver (ADR-001, seção 2.3): automação, versão com a
// receita, execuções e registros. Nomes de pessoas, etapas, caixas e modelos são
// dados da conta (chegam do servidor em pt-BR); as frases da tela moram no i18n
// (AUTOMACAO_LIVRE). Na F5 este arquivo é trocado pelo endpoint.

// --- Coisas da conta ---------------------------------------------------------

export const FUNIS = [
  { id: 'comercial', nome: 'Comercial' },
  { id: 'leads', nome: 'Leads do anúncio' },
  { id: 'carteira', nome: 'Carteira de clientes' },
];

export const ETAPAS = [
  { id: 'novo_contato', nome: 'Novo contato', funil: 'comercial' },
  { id: 'orcamento_enviado', nome: 'Orçamento enviado', funil: 'comercial' },
  { id: 'negociacao', nome: 'Negociação', funil: 'comercial' },
  { id: 'fechado', nome: 'Fechado', funil: 'comercial' },
  { id: 'lead_novo', nome: 'Lead novo', funil: 'leads' },
  { id: 'cotacao_pme', nome: 'Cotação PME', funil: 'leads' },
  { id: 'cotacao_individual', nome: 'Cotação individual', funil: 'leads' },
  { id: 'apolice_ativa', nome: 'Apólice ativa', funil: 'carteira' },
  { id: 'renovacao', nome: 'Renovação', funil: 'carteira' },
];

export const CAMPOS_DO_CARTAO = [
  { id: 'vencimento_apolice', nome: 'Vencimento da apólice', tipo: 'data' },
  { id: 'produto_interesse', nome: 'Produto de interesse', tipo: 'texto' },
  { id: 'melhor_horario', nome: 'Melhor horário para ligar', tipo: 'texto' },
];

export const EQUIPES = [
  { id: 'pme', nome: 'Equipe PME' },
  { id: 'comercial', nome: 'Time comercial' },
  { id: 'pos_venda', nome: 'Pós-venda' },
];

export const CAIXAS = [
  { id: 1, nome: 'WhatsApp Vendas' },
  { id: 2, nome: 'Instagram da loja' },
];

// Texto do modelo como o motor guarda: pedaços de texto e variáveis
// estruturadas ({ $valor }), nunca Liquid.
export const MODELOS_WHATSAPP = [
  {
    id: 'retomada_orcamento',
    nome: 'Retomada de orçamento',
    texto: [
      'Oi ',
      { $valor: 'contato.nome' },
      ', tudo bem? Passando para saber se ficou alguma dúvida sobre o orçamento. Posso te ajudar a fechar?',
    ],
  },
  {
    id: 'renovacao_aviso',
    nome: 'Aviso de renovação',
    texto: [
      'Oi ',
      { $valor: 'contato.nome' },
      '! Seu seguro vence em ',
      { $valor: 'card.campo.vencimento_apolice' },
      '. Quer que eu já prepare a renovação para você?',
    ],
  },
  {
    id: 'boas_vindas',
    nome: 'Boas-vindas',
    texto: [
      'Oi ',
      { $valor: 'contato.nome' },
      ', que bom ter você aqui! Já vamos te responder.',
    ],
  },
];

// --- Receitas (versão = receita imutável) -------------------------------------

const FREIO_PADRAO = {
  nao_repetir_dias: 7,
  por_hora: 30,
  mensagem_minutos: 60,
};

const RECEITA_RENOVACAO = {
  gatilho: { tipo: 'campo_data', campo: 'vencimento_apolice', dias: 30 },
  condicoes: [{ tipo: 'cartao_na_etapa', etapa: 'apolice_ativa' }],
  passos: [
    { id: 'r1', tipo: 'mover_cartao', etapa: 'renovacao' },
    {
      id: 'r2',
      tipo: 'criar_tarefa',
      titulo: 'Ligar para renovar',
      para: 'responsavel',
    },
    { id: 'r3', tipo: 'mandar_modelo', modelo: 'renovacao_aviso' },
    {
      id: 'r4',
      tipo: 'esperar_resposta',
      dias: 3,
      caminhos: [
        {
          chave: 'respondeu',
          passos: [
            {
              id: 'r5',
              tipo: 'decisor',
              pergunta: 'Ele quer renovar?',
              caminhos: [
                {
                  chave: 'renovar',
                  rotulo: 'Quer renovar',
                  passos: [
                    {
                      id: 'r6',
                      tipo: 'criar_tarefa',
                      titulo: 'Emitir renovação',
                      para: 'responsavel',
                    },
                  ],
                },
                {
                  chave: 'cotar',
                  rotulo: 'Quer cotar outra opção',
                  passos: [
                    {
                      id: 'r7',
                      tipo: 'criar_tarefa',
                      titulo: 'Cotar outras opções',
                      para: 'responsavel',
                    },
                  ],
                },
                {
                  chave: 'nao_quer',
                  rotulo: 'Não quer renovar',
                  passos: [
                    {
                      id: 'r8',
                      tipo: 'fechar_cartao',
                      resultado: 'perdido',
                      motivo: 'Não quis renovar',
                    },
                  ],
                },
                {
                  chave: 'nenhuma',
                  passos: [
                    {
                      id: 'r9',
                      tipo: 'criar_tarefa',
                      titulo: 'Ler a resposta do cliente',
                      para: 'dono',
                    },
                  ],
                },
              ],
            },
          ],
        },
        {
          chave: 'venceu',
          passos: [{ id: 'r10', tipo: 'avisar_equipe', para: 'responsavel' }],
        },
      ],
    },
  ],
  meta: { tipo: 'cartao_ganho' },
  freio: FREIO_PADRAO,
};

const RECEITA_ORCAMENTO = {
  gatilho: { tipo: 'cartao_parado', etapa: 'orcamento_enviado', dias: 2 },
  condicoes: [{ tipo: 'valor_maior', valor: 300 }],
  passos: [
    { id: 'o1', tipo: 'mandar_modelo', modelo: 'retomada_orcamento' },
    {
      id: 'o2',
      tipo: 'esperar_resposta',
      dias: 2,
      caminhos: [
        {
          chave: 'respondeu',
          passos: [
            {
              id: 'o3',
              tipo: 'criar_tarefa',
              titulo: 'Retomar proposta',
              para: 'responsavel',
            },
          ],
        },
        {
          chave: 'venceu',
          passos: [
            {
              id: 'o4',
              tipo: 'fechar_cartao',
              resultado: 'perdido',
              motivo: 'Sem resposta',
            },
          ],
        },
      ],
    },
  ],
  meta: { tipo: 'cartao_ganho' },
  freio: FREIO_PADRAO,
};

const RECEITA_LEAD = {
  gatilho: { tipo: 'cartao_criado_formulario' },
  condicoes: [],
  passos: [
    {
      id: 'l1',
      tipo: 'extrair_ia',
      campos: ['produto_interesse', 'melhor_horario'],
    },
    {
      id: 'l2',
      tipo: 'atualizar_cartao',
      campos: ['produto_interesse', 'melhor_horario'],
    },
    {
      id: 'l3',
      tipo: 'decisor',
      pergunta: 'É plano para empresa ou individual?',
      caminhos: [
        {
          chave: 'pme',
          rotulo: 'Empresa (PME)',
          passos: [
            { id: 'l4', tipo: 'atribuir_equipe', equipe: 'pme' },
            { id: 'l5', tipo: 'mover_cartao', etapa: 'cotacao_pme' },
            {
              id: 'l6',
              tipo: 'mandar_mensagem',
              texto: [
                'Oi ',
                { $valor: 'contato.nome' },
                ', já vou separar as opções para sua empresa.',
              ],
            },
          ],
        },
        {
          chave: 'individual',
          rotulo: 'Individual',
          passos: [
            { id: 'l7', tipo: 'mover_cartao', etapa: 'cotacao_individual' },
          ],
        },
        {
          chave: 'nenhuma',
          passos: [
            {
              id: 'l8',
              tipo: 'criar_tarefa',
              titulo: 'Ver este lead',
              para: 'dono',
            },
          ],
        },
      ],
    },
    { id: 'l9', tipo: 'esperar', dias: 2 },
    {
      id: 'l10',
      tipo: 'se',
      condicao: { tipo: 'cartao_na_etapa', etapa: 'lead_novo' },
      caminhos: [
        {
          chave: 'sim',
          passos: [
            {
              id: 'l11',
              tipo: 'criar_tarefa',
              titulo: 'Ligar para o lead',
              para: 'responsavel',
            },
          ],
        },
        { chave: 'nao', passos: [] },
      ],
    },
  ],
  meta: null,
  freio: { ...FREIO_PADRAO, ia_por_dia: 1000 },
};

const RECEITA_AGRADECER = {
  gatilho: { tipo: 'conversa_resolvida' },
  condicoes: [],
  passos: [
    {
      id: 'a1',
      tipo: 'mandar_mensagem',
      texto: [
        'Obrigado pelo contato, ',
        { $valor: 'contato.nome' },
        '! Qualquer coisa, é só chamar.',
      ],
    },
  ],
  meta: null,
  freio: FREIO_PADRAO,
};

const RECEITA_BOAS_VINDAS = {
  gatilho: { tipo: 'conversa_nova' },
  condicoes: [{ tipo: 'caixa', caixa: 1 }],
  passos: [{ id: 'b1', tipo: 'mandar_modelo', modelo: 'boas_vindas' }],
  meta: null,
  freio: FREIO_PADRAO,
};

const RECEITA_NEGOCIACAO_ANTIGA = {
  gatilho: { tipo: 'cartao_entrou', etapa: 'negociacao' },
  condicoes: [],
  passos: [
    {
      id: 'n1',
      tipo: 'criar_tarefa',
      titulo: 'Mandar contrato',
      para: 'responsavel',
    },
  ],
  meta: null,
  freio: FREIO_PADRAO,
};

const RECEITA_NEGOCIACAO_NOVA = {
  gatilho: { tipo: 'cartao_entrou', etapa: 'negociacao' },
  condicoes: [{ tipo: 'valor_maior', valor: 2000 }],
  passos: [
    { id: 'v1', tipo: 'avisar_equipe', para: 'responsavel' },
    { id: 'v2', tipo: 'resumir_ia' },
  ],
  meta: null,
  freio: FREIO_PADRAO,
};

// --- Automações ----------------------------------------------------------------

// origem: de onde ela escuta ("conversa" ou "funil"). jeitoAntigo: veio de um
// motor antigo (regra do Chatwoot ou automação de etapa) e ainda não foi
// trazida. pacote: receita de um pacote de segmento.
export const AUTOMACOES_INICIAIS = [
  {
    id: 1,
    nome: 'Avisar a renovação 30 dias antes',
    ativa: false,
    origem: 'funil',
    jeitoAntigo: false,
    criadaPor: 'receita',
    pacote: 'Seguros',
    ligadaPor: null,
    estatisticas: { semana: 0, pararam: 0 },
    noMeio: 0,
  },
  {
    id: 2,
    nome: 'Retomar orçamento parado',
    ativa: true,
    origem: 'funil',
    jeitoAntigo: false,
    criadaPor: 'receita',
    pacote: null,
    ligadaPor: 'Juliana Prado',
    estatisticas: { semana: 12, pararam: 1 },
    noMeio: 8,
  },
  {
    id: 3,
    nome: 'Organizar lead do formulário do anúncio',
    ativa: false,
    origem: 'funil',
    jeitoAntigo: false,
    criadaPor: 'guia',
    pacote: null,
    ligadaPor: null,
    estatisticas: { semana: 0, pararam: 0 },
    noMeio: 0,
  },
  {
    id: 4,
    nome: 'Agradecer ao encerrar',
    ativa: true,
    origem: 'conversa',
    jeitoAntigo: true,
    criadaPor: 'manual',
    pacote: null,
    ligadaPor: 'Rafael Monteiro',
    estatisticas: { semana: 41, pararam: 0 },
    noMeio: 0,
  },
  {
    id: 5,
    nome: 'Tarefa de contrato ao entrar em Negociação',
    ativa: true,
    origem: 'funil',
    jeitoAntigo: true,
    criadaPor: 'manual',
    pacote: null,
    ligadaPor: 'Juliana Prado',
    estatisticas: { semana: 5, pararam: 0 },
    noMeio: 0,
    etapaAntiga: 'negociacao',
  },
  {
    id: 6,
    nome: 'Boas-vindas no WhatsApp Vendas',
    ativa: true,
    origem: 'conversa',
    jeitoAntigo: false,
    criadaPor: 'guia',
    pacote: null,
    ligadaPor: 'Rafael Monteiro',
    estatisticas: { semana: 27, pararam: 2 },
    noMeio: 0,
  },
  {
    id: 7,
    nome: 'Avisar quando negócio grande entrar em Negociação',
    ativa: true,
    origem: 'funil',
    jeitoAntigo: false,
    criadaPor: 'manual',
    pacote: null,
    ligadaPor: 'Juliana Prado',
    estatisticas: { semana: 3, pararam: 0 },
    noMeio: 0,
  },
];

// Uma versão por automação no começo; salvar cria a próxima (imutável).
export const VERSOES_INICIAIS = [
  {
    id: 11,
    automacaoId: 1,
    numero: 1,
    autor: 'Receita do pacote',
    receita: RECEITA_RENOVACAO,
  },
  {
    id: 21,
    automacaoId: 2,
    numero: 1,
    autor: 'Juliana Prado',
    receita: RECEITA_ORCAMENTO,
  },
  {
    id: 22,
    automacaoId: 2,
    numero: 2,
    autor: 'Juliana Prado',
    receita: RECEITA_ORCAMENTO,
  },
  { id: 31, automacaoId: 3, numero: 1, autor: 'Guia', receita: RECEITA_LEAD },
  {
    id: 41,
    automacaoId: 4,
    numero: 1,
    autor: 'Rafael Monteiro',
    receita: RECEITA_AGRADECER,
  },
  {
    id: 51,
    automacaoId: 5,
    numero: 1,
    autor: 'Juliana Prado',
    receita: RECEITA_NEGOCIACAO_ANTIGA,
  },
  {
    id: 61,
    automacaoId: 6,
    numero: 1,
    autor: 'Guia',
    receita: RECEITA_BOAS_VINDAS,
  },
  {
    id: 71,
    automacaoId: 7,
    numero: 1,
    autor: 'Juliana Prado',
    receita: RECEITA_NEGOCIACAO_NOVA,
  },
];

// Receitas para começar. As gerais têm o texto no i18n (RECEITAS.<chave>); as
// do pacote do segmento chegam prontas do servidor, já no idioma da conta.
// `exemplo`: a automação de exemplo cujos alvos o ensaio usa.
export const RECEITAS = [
  {
    chave: 'ORCAMENTO_PARADO',
    exemplo: 2,
    icone: 'i-lucide-hand-coins',
    tom: 'bg-n-teal-3 text-n-teal-11',
    receita: RECEITA_ORCAMENTO,
  },
  {
    chave: 'LEAD_FORMULARIO',
    exemplo: 3,
    icone: 'i-lucide-sparkles',
    tom: 'bg-n-iris-3 text-n-iris-11',
    receita: RECEITA_LEAD,
  },
  {
    chave: 'AGRADECER',
    exemplo: 4,
    icone: 'i-lucide-heart-handshake',
    tom: 'bg-n-ruby-3 text-n-ruby-11',
    receita: RECEITA_AGRADECER,
  },
  {
    chave: 'BOAS_VINDAS',
    exemplo: 6,
    icone: 'i-lucide-message-circle-heart',
    tom: 'bg-n-blue-3 text-n-blue-11',
    receita: RECEITA_BOAS_VINDAS,
  },
  {
    chave: 'RENOVACAO',
    exemplo: 1,
    icone: 'i-lucide-calendar-clock',
    tom: 'bg-n-amber-3 text-n-amber-11',
    receita: RECEITA_RENOVACAO,
    pacote: {
      nome: 'Seguros',
      titulo: 'Avisar a renovação 30 dias antes',
      texto:
        'Faltando 30 dias para o vencimento da apólice, o cartão vai para Renovação, o responsável ganha a tarefa e o cliente recebe o aviso.',
    },
  },
];

// --- Execuções e registros -----------------------------------------------------

// Cartões do funil (para o painel da etapa, o do cartão e o ensaio).
export const CARTOES = [
  {
    id: 101,
    nome: 'Marcos Albuquerque',
    etapa: 'orcamento_enviado',
    valor: 1250,
    diasNaEtapa: 3,
    responsavel: 'Juliana Prado',
  },
  {
    id: 102,
    nome: 'Padaria Pão de Mel',
    etapa: 'orcamento_enviado',
    valor: 480,
    diasNaEtapa: 1,
    responsavel: 'Rafael Monteiro',
  },
  {
    id: 103,
    nome: 'Thiago Mendes',
    etapa: 'orcamento_enviado',
    valor: 180,
    diasNaEtapa: 5,
    responsavel: 'Juliana Prado',
  },
  {
    id: 104,
    nome: 'Clínica Sorriso Leve',
    etapa: 'novo_contato',
    valor: 900,
    diasNaEtapa: 0,
    responsavel: 'Rafael Monteiro',
  },
  {
    id: 105,
    nome: 'Renata Okada',
    etapa: 'negociacao',
    valor: 3200,
    diasNaEtapa: 2,
    responsavel: 'Juliana Prado',
  },
  {
    id: 106,
    nome: 'Oficina Dois Irmãos',
    etapa: 'fechado',
    valor: 2100,
    diasNaEtapa: 9,
    responsavel: 'Rafael Monteiro',
  },
  {
    id: 201,
    nome: 'Beatriz Lacerda',
    etapa: 'apolice_ativa',
    valor: 2400,
    diasNaEtapa: 330,
    responsavel: 'Juliana Prado',
  },
  {
    id: 202,
    nome: 'Transportes Vale Verde',
    etapa: 'renovacao',
    valor: 8900,
    diasNaEtapa: 4,
    responsavel: 'Rafael Monteiro',
  },
  {
    id: 301,
    nome: 'Carla Nogueira',
    etapa: 'lead_novo',
    valor: 0,
    diasNaEtapa: 0,
    responsavel: 'Equipe PME',
  },
  {
    id: 302,
    nome: 'Fernando Rocha',
    etapa: 'lead_novo',
    valor: 0,
    diasNaEtapa: 0,
    responsavel: 'Rafael Monteiro',
  },
];

// Execuções em andamento. `ate`: até quando espera.
export const EXECUCOES_INICIAIS = [
  {
    id: 9001,
    automacaoId: 2,
    versaoId: 22,
    cartaoId: 101,
    estado: 'esperando_resposta',
    ate: '2026-11-05T13:00:00Z',
  },
  {
    id: 9002,
    automacaoId: 7,
    versaoId: 71,
    cartaoId: 101,
    estado: 'esperando',
    ate: '2026-11-02T12:00:00Z',
  },
  {
    id: 9003,
    automacaoId: 2,
    versaoId: 22,
    cartaoId: 102,
    estado: 'esperando_resposta',
    ate: '2026-11-03T15:30:00Z',
  },
];

// Uma linha por passo. `chave` é a frase (REGISTROS.<chave>) com `params`.
export const REGISTROS_INICIAIS = [
  {
    id: 1,
    automacaoId: 2,
    cartaoId: 101,
    alvo: 'Marcos Albuquerque',
    em: '2026-10-30T13:02:00Z',
    resultado: 'esperando',
    chave: 'ESPERANDO_RESPOSTA',
    params: { ate: '2026-11-05T13:00:00Z' },
  },
  {
    id: 2,
    automacaoId: 2,
    cartaoId: 101,
    alvo: 'Marcos Albuquerque',
    em: '2026-10-30T13:01:00Z',
    resultado: 'feito',
    chave: 'MANDOU_MODELO',
    params: { modelo: 'Retomada de orçamento' },
  },
  {
    id: 3,
    automacaoId: 2,
    cartaoId: 106,
    alvo: 'Oficina Dois Irmãos',
    em: '2026-10-29T18:40:00Z',
    resultado: 'pulou',
    chave: 'PULOU_SAIU_DA_ETAPA',
    params: {},
  },
  {
    id: 4,
    automacaoId: 2,
    cartaoId: 103,
    alvo: 'Thiago Mendes',
    em: '2026-10-29T12:10:00Z',
    resultado: 'pulou',
    chave: 'NAO_COMECOU_VALOR',
    params: { valor: 'R$ 180,00' },
  },
  {
    id: 5,
    automacaoId: 2,
    cartaoId: 105,
    alvo: 'Renata Okada',
    em: '2026-10-28T20:15:00Z',
    resultado: 'parou',
    chave: 'PAROU_LOOPING',
    params: {},
  },
  {
    id: 6,
    automacaoId: 2,
    cartaoId: 104,
    alvo: 'Clínica Sorriso Leve',
    em: '2026-10-28T14:00:00Z',
    resultado: 'feito',
    chave: 'CRIOU_TAREFA',
    params: { titulo: 'Retomar proposta' },
  },
  {
    id: 7,
    automacaoId: 2,
    cartaoId: 102,
    alvo: 'Padaria Pão de Mel',
    em: '2026-10-27T15:30:00Z',
    resultado: 'falhou',
    chave: 'FALHOU_MODELO',
    params: {},
  },
  {
    id: 8,
    automacaoId: 2,
    cartaoId: 106,
    alvo: 'Oficina Dois Irmãos',
    em: '2026-10-26T11:00:00Z',
    resultado: 'parou',
    chave: 'PAROU_META_GANHO',
    params: {},
  },
  {
    id: 9,
    automacaoId: 2,
    cartaoId: 102,
    alvo: 'Padaria Pão de Mel',
    em: '2026-10-26T10:00:00Z',
    resultado: 'pulou',
    chave: 'PULOU_REPETIR',
    params: { dias: 7 },
  },
  {
    id: 10,
    automacaoId: 7,
    cartaoId: 101,
    alvo: 'Marcos Albuquerque',
    em: '2026-10-30T12:00:00Z',
    resultado: 'feito',
    chave: 'AVISOU',
    params: { pessoa: 'Juliana Prado' },
  },
  {
    id: 11,
    automacaoId: 6,
    cartaoId: null,
    alvo: 'Patrícia Lemos',
    em: '2026-10-30T11:20:00Z',
    resultado: 'feito',
    chave: 'MANDOU_MODELO',
    params: { modelo: 'Boas-vindas' },
  },
  {
    id: 12,
    automacaoId: 6,
    cartaoId: null,
    alvo: 'Diego Furtado',
    em: '2026-10-30T09:05:00Z',
    resultado: 'pulou',
    chave: 'PULOU_TETO_MENSAGEM',
    params: { minutos: 60 },
  },
  {
    id: 13,
    automacaoId: 4,
    cartaoId: null,
    alvo: 'Sônia Barreto',
    em: '2026-10-30T10:45:00Z',
    resultado: 'feito',
    chave: 'MANDOU_MENSAGEM',
    params: {},
  },
];

// --- Ensaio -------------------------------------------------------------------

// Quem dá para ensaiar, por automação, com o que aconteceria em cada caminho
// (`caminhos`: id do passo → chave do caminho) e os valores das variáveis.
export const ALVOS_DE_ENSAIO = [
  {
    id: 101,
    automacoes: [2, 7],
    tipo: 'cartao',
    nome: 'Marcos Albuquerque',
    detalheChave: 'CARTAO_DETALHE',
    detalhe: { etapa: 'Orçamento enviado', dias: 3, valor: 'R$ 1.250,00' },
    valores: { 'contato.nome': 'Marcos' },
    caminhos: { o2: 'venceu' },
  },
  {
    id: 102,
    automacoes: [2],
    tipo: 'cartao',
    nome: 'Padaria Pão de Mel',
    detalheChave: 'CARTAO_DETALHE',
    detalhe: { etapa: 'Orçamento enviado', dias: 1, valor: 'R$ 480,00' },
    valores: { 'contato.nome': 'Lúcia' },
    caminhos: { o2: 'respondeu' },
  },
  {
    id: 103,
    automacoes: [2],
    tipo: 'cartao',
    nome: 'Thiago Mendes',
    detalheChave: 'CARTAO_DETALHE',
    detalhe: { etapa: 'Orçamento enviado', dias: 5, valor: 'R$ 180,00' },
    valores: { 'contato.nome': 'Thiago' },
    naoComecaChave: 'NAO_COMECA_VALOR',
    naoComeca: { valor: 'R$ 180,00', minimo: 'R$ 300,00' },
  },
  {
    id: 201,
    automacoes: [1],
    tipo: 'cartao',
    nome: 'Beatriz Lacerda',
    detalheChave: 'CARTAO_DATA',
    detalhe: { campo: 'Vencimento da apólice', data: '29/11/2026' },
    valores: {
      'contato.nome': 'Beatriz',
      'card.campo.vencimento_apolice': '29/11/2026',
    },
    caminhos: { r4: 'respondeu', r5: 'renovar' },
  },
  {
    id: 202,
    automacoes: [1],
    tipo: 'cartao',
    nome: 'Transportes Vale Verde',
    detalheChave: 'CARTAO_DATA',
    detalhe: { campo: 'Vencimento da apólice', data: '30/11/2026' },
    valores: {
      'contato.nome': 'Sr. Álvaro',
      'card.campo.vencimento_apolice': '30/11/2026',
    },
    caminhos: { r4: 'venceu' },
  },
  {
    id: 301,
    automacoes: [3],
    tipo: 'cartao',
    nome: 'Carla Nogueira',
    detalheChave: 'CARTAO_FORMULARIO',
    detalhe: {
      texto:
        'Quero um plano para os 12 funcionários da minha loja, de manhã é melhor.',
    },
    valores: {
      'contato.nome': 'Carla',
      produto_interesse: 'Plano empresarial',
      melhor_horario: 'Manhã',
    },
    caminhos: { l3: 'pme', l10: 'nao' },
  },
  {
    id: 302,
    automacoes: [3],
    tipo: 'cartao',
    nome: 'Fernando Rocha',
    detalheChave: 'CARTAO_FORMULARIO',
    detalhe: { texto: 'Queria saber o preço.' },
    valores: {
      'contato.nome': 'Fernando',
      produto_interesse: '',
      melhor_horario: '',
    },
    caminhos: { l3: 'nenhuma', l10: 'sim' },
  },
  {
    id: 401,
    automacoes: [4, 6],
    tipo: 'conversa',
    nome: 'Sônia Barreto',
    detalheChave: 'CONVERSA_DETALHE',
    detalhe: { caixa: 'WhatsApp Vendas' },
    valores: { 'contato.nome': 'Sônia' },
    caminhos: {},
  },
  {
    id: 402,
    automacoes: [5, 7],
    tipo: 'cartao',
    nome: 'Renata Okada',
    detalheChave: 'CARTAO_DETALHE',
    detalhe: { etapa: 'Negociação', dias: 2, valor: 'R$ 3.200,00' },
    valores: { 'contato.nome': 'Renata' },
    caminhos: {},
  },
];

export const PESSOAS_DE_EXEMPLO = {
  responsavel: 'Juliana Prado',
  dono: 'Rafael Monteiro',
};
