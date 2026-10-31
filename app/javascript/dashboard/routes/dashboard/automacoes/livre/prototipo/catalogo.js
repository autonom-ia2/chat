// #2414 F0 — o catálogo de passos do protótipo. No motor ele é gerado
// (`lib/operator_guide/automacao-passos.json`, ADR-001 2.2) e o Guia e o editor
// leem o mesmo arquivo. Aqui: o tipo de cada passo, o grupo do seletor, os
// campos que o "Alterar" mostra (um renderizador por tipo de campo), se manda
// para o cliente (sem volta) e o custo da IA. A frase de cada tipo mora no i18n
// em AUTOMACAO_LIVRE.PASSOS.<TIPO>.

export const GRUPOS = [
  { chave: 'CONVERSA', icone: 'i-lucide-message-circle' },
  { chave: 'CARTAO', icone: 'i-lucide-square-kanban' },
  { chave: 'CONTATO', icone: 'i-lucide-user-round' },
  { chave: 'RETORNO', icone: 'i-lucide-bell-ring' },
  { chave: 'AGENDA', icone: 'i-lucide-calendar-days' },
  { chave: 'IA', icone: 'i-lucide-sparkles' },
  { chave: 'CONTROLE', icone: 'i-lucide-timer' },
];

// Custo por vez, em reais, cobrado na chave de IA da conta.
export const TIPOS_DE_PASSO = {
  mandar_mensagem: {
    grupo: 'CONVERSA',
    icone: 'i-lucide-send',
    semVolta: true,
    campos: [{ nome: 'texto', tipo: 'mensagem' }],
  },
  mandar_modelo: {
    grupo: 'CONVERSA',
    icone: 'i-lucide-message-square-text',
    semVolta: true,
    campos: [{ nome: 'modelo', tipo: 'modelo' }],
  },
  avisar_equipe: {
    grupo: 'CONVERSA',
    icone: 'i-lucide-megaphone',
    campos: [{ nome: 'para', tipo: 'pessoa' }],
  },
  atribuir_equipe: {
    grupo: 'CONVERSA',
    icone: 'i-lucide-users-round',
    campos: [{ nome: 'equipe', tipo: 'equipe' }],
  },
  mover_cartao: {
    grupo: 'CARTAO',
    icone: 'i-lucide-move-right',
    campos: [{ nome: 'etapa', tipo: 'etapa' }],
  },
  atualizar_cartao: {
    grupo: 'CARTAO',
    icone: 'i-lucide-pencil-line',
    campos: [{ nome: 'campos', tipo: 'campos' }],
  },
  fechar_cartao: {
    grupo: 'CARTAO',
    icone: 'i-lucide-circle-x',
    campos: [
      { nome: 'resultado', tipo: 'resultado' },
      { nome: 'motivo', tipo: 'texto' },
    ],
  },
  etiquetar_contato: {
    grupo: 'CONTATO',
    icone: 'i-lucide-tag',
    campos: [{ nome: 'etiqueta', tipo: 'texto' }],
  },
  criar_tarefa: {
    grupo: 'RETORNO',
    icone: 'i-lucide-list-checks',
    campos: [
      { nome: 'titulo', tipo: 'texto' },
      { nome: 'para', tipo: 'pessoa' },
    ],
  },
  oferecer_horarios: {
    grupo: 'AGENDA',
    icone: 'i-lucide-calendar-plus',
    semVolta: true,
    campos: [],
  },
  extrair_ia: {
    grupo: 'IA',
    icone: 'i-lucide-scan-text',
    custo: 0.01,
    campos: [{ nome: 'campos', tipo: 'campos' }],
  },
  decisor: {
    grupo: 'IA',
    icone: 'i-lucide-split',
    custo: 0.02,
    campos: [{ nome: 'pergunta', tipo: 'texto' }],
  },
  resumir_ia: {
    grupo: 'IA',
    icone: 'i-lucide-file-text',
    custo: 0.01,
    campos: [],
  },
  esperar: {
    grupo: 'CONTROLE',
    icone: 'i-lucide-hourglass',
    campos: [{ nome: 'dias', tipo: 'dias' }],
  },
  esperar_resposta: {
    grupo: 'CONTROLE',
    icone: 'i-lucide-message-circle-question',
    campos: [{ nome: 'dias', tipo: 'dias' }],
  },
  se: {
    grupo: 'CONTROLE',
    icone: 'i-lucide-git-branch',
    campos: [{ nome: 'condicao', tipo: 'condicao' }],
  },
  parar: {
    grupo: 'CONTROLE',
    icone: 'i-lucide-octagon-x',
    campos: [],
  },
  acao_plataforma: {
    grupo: 'PLATAFORMA',
    icone: 'i-lucide-blocks',
    campos: [],
  },
};

// "Todas as ações da plataforma": um recorte do que o catálogo do Guia libera
// (allowlist). A frase está em AUTOMACAO_LIVRE.PLATAFORMA.<chave>. Ação sem
// frase aparece como "Ação avançada" e nunca some.
export const ACOES_DA_PLATAFORMA = [
  { chave: 'NOTA_PRIVADA' },
  { chave: 'RESOLVER_CONVERSA' },
  { chave: 'ADIAR_CONVERSA' },
  { chave: 'PRIORIDADE_ALTA' },
  { chave: 'ATRIBUIR_RODIZIO' },
  { chave: 'ETIQUETA_CONVERSA' },
  { chave: 'TIRAR_ETIQUETA' },
  { chave: 'CAMPO_CONTATO' },
  { chave: 'EMPRESA_CONTATO' },
  { chave: 'CRIAR_CARTAO' },
  { chave: 'ARQUIVAR_CARTAO' },
  { chave: 'PRODUTO_CARTAO' },
  { chave: 'CRIAR_EVENTO' },
  { chave: 'CANCELAR_EVENTO' },
  { chave: 'MANDAR_EMAIL', semVolta: true },
  { chave: 'PESQUISA_SATISFACAO', semVolta: true },
  { chave: 'LINK_PAGAMENTO', semVolta: true },
  { chave: 'SEM_FRASE', semFrase: true },
];

export const TIPOS_DE_GATILHO = [
  { tipo: 'conversa_nova', campos: [] },
  { tipo: 'mensagem_recebida', campos: [] },
  { tipo: 'conversa_resolvida', campos: [] },
  { tipo: 'cartao_entrou', campos: [{ nome: 'etapa', tipo: 'etapa' }] },
  {
    tipo: 'cartao_parado',
    campos: [
      { nome: 'etapa', tipo: 'etapa' },
      { nome: 'dias', tipo: 'dias' },
    ],
  },
  {
    tipo: 'campo_data',
    campos: [
      { nome: 'campo', tipo: 'campo_data' },
      { nome: 'dias', tipo: 'dias' },
    ],
  },
  { tipo: 'cartao_criado_formulario', campos: [] },
];

export const TIPOS_DE_CONDICAO = [
  { tipo: 'cartao_na_etapa', campos: [{ nome: 'etapa', tipo: 'etapa' }] },
  { tipo: 'valor_maior', campos: [{ nome: 'valor', tipo: 'numero' }] },
  { tipo: 'caixa', campos: [{ nome: 'caixa', tipo: 'caixa' }] },
  { tipo: 'fora_do_horario', campos: [] },
];

export const TIPOS_DE_META = ['nenhuma', 'cartao_ganho', 'cartao_perdido'];

// O que um passo novo já traz, para a frase nunca sair com buraco.
const PADROES = {
  mandar_mensagem: () => ({
    texto: ['Oi ', { $valor: 'contato.nome' }, ', tudo bem?'],
  }),
  mandar_modelo: () => ({ modelo: 'retomada_orcamento' }),
  avisar_equipe: () => ({ para: 'responsavel' }),
  atribuir_equipe: () => ({ equipe: 'comercial' }),
  mover_cartao: () => ({ etapa: 'negociacao' }),
  atualizar_cartao: () => ({ campos: ['produto_interesse'] }),
  fechar_cartao: () => ({ resultado: 'perdido', motivo: 'Sem resposta' }),
  etiquetar_contato: () => ({ etiqueta: 'retomar' }),
  criar_tarefa: () => ({ titulo: 'Ligar para o cliente', para: 'responsavel' }),
  extrair_ia: () => ({ campos: ['produto_interesse'] }),
  decisor: () => ({
    pergunta: 'O cliente quer seguir?',
    caminhos: [
      { chave: 'sim', rotulo: 'Quer seguir', passos: [] },
      { chave: 'nao', rotulo: 'Não quer', passos: [] },
      { chave: 'nenhuma', passos: [] },
    ],
  }),
  esperar: () => ({ dias: 1 }),
  esperar_resposta: () => ({
    dias: 2,
    caminhos: [
      { chave: 'respondeu', passos: [] },
      { chave: 'venceu', passos: [] },
    ],
  }),
  se: () => ({
    condicao: { tipo: 'cartao_na_etapa', etapa: 'orcamento_enviado' },
    caminhos: [
      { chave: 'sim', passos: [] },
      { chave: 'nao', passos: [] },
    ],
  }),
};

let contador = 0;
export const novoId = () => {
  contador += 1;
  return `novo${contador}`;
};

export const novoPasso = (tipo, extra = {}) => ({
  id: novoId(),
  tipo,
  ...(PADROES[tipo] ? PADROES[tipo]() : {}),
  ...extra,
});

export const PADROES_DE_GATILHO = {
  cartao_entrou: { etapa: 'orcamento_enviado' },
  cartao_parado: { etapa: 'orcamento_enviado', dias: 2 },
  campo_data: { campo: 'vencimento_apolice', dias: 30 },
};

export const PADROES_DE_CONDICAO = {
  cartao_na_etapa: { etapa: 'orcamento_enviado' },
  valor_maior: { valor: 300 },
  caixa: { caixa: 1 },
};

export const FREIO_PADRAO = {
  nao_repetir_dias: 7,
  por_hora: 30,
  mensagem_minutos: 60,
};
