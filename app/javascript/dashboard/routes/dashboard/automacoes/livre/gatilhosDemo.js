// #2499 (F6+F8) — PROTÓTIPO. Adaptador falso dos gatilhos novos, dos painéis da
// etapa e do card e do passo webhook. É o que a tela mostra enquanto o servidor
// não tem o catálogo dos gatilhos (Catalogo.gatilhos) nem os endpoints dos
// painéis. Na implementação, cada função daqui vira a chamada da API com a
// mesma forma, e este arquivo sai.
const G = 'AUTOMACAO_LIVRE.GATILHOS_F6';

// Os grupos do seletor, na ordem da tela.
export const GRUPOS = ['CONVERSA', 'MENSAGEM', 'CARD', 'TEMPO', 'REUNIAO'];

// O que cada gatilho pede além do tipo. `peca` diz qual campo a tela mostra.
const ETAPA = { nome: 'etapa_id', peca: 'etapa', obrigatorio: true };
const DIAS = { nome: 'dias', peca: 'dias', obrigatorio: true };
const HORA = { nome: 'hora', peca: 'hora', obrigatorio: true };

export const GATILHOS = [
  { tipo: 'conversa.criada', grupo: 'CONVERSA', alvo: 'conversa' },
  { tipo: 'conversa.aberta', grupo: 'CONVERSA', alvo: 'conversa' },
  { tipo: 'conversa.resolvida', grupo: 'CONVERSA', alvo: 'conversa' },
  {
    tipo: 'conversa.responsavel_trocado',
    grupo: 'CONVERSA',
    alvo: 'conversa',
    novo: true,
  },
  {
    tipo: 'conversa.time_trocado',
    grupo: 'CONVERSA',
    alvo: 'conversa',
    novo: true,
  },
  {
    tipo: 'conversa.etiqueta_posta',
    grupo: 'CONVERSA',
    alvo: 'conversa',
    novo: true,
    parametros: [{ nome: 'etiqueta', peca: 'etiqueta', obrigatorio: true }],
  },
  {
    tipo: 'conversa.etiqueta_tirada',
    grupo: 'CONVERSA',
    alvo: 'conversa',
    novo: true,
    parametros: [{ nome: 'etiqueta', peca: 'etiqueta', obrigatorio: true }],
  },
  {
    tipo: 'contato.etiqueta_posta',
    grupo: 'CONVERSA',
    alvo: 'contato',
    novo: true,
    parametros: [{ nome: 'etiqueta', peca: 'etiqueta', obrigatorio: true }],
  },
  {
    tipo: 'contato.etiqueta_tirada',
    grupo: 'CONVERSA',
    alvo: 'contato',
    novo: true,
    parametros: [{ nome: 'etiqueta', peca: 'etiqueta', obrigatorio: true }],
  },
  { tipo: 'mensagem.criada', grupo: 'MENSAGEM', alvo: 'conversa' },
  { tipo: 'mensagem.falhou', grupo: 'MENSAGEM', alvo: 'conversa', novo: true },
  {
    tipo: 'card.criado',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [{ nome: 'funil_id', peca: 'funil', obrigatorio: false }],
  },
  {
    tipo: 'card.responsavel_trocado',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
  },
  {
    tipo: 'card.entrou_na_etapa',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [ETAPA],
  },
  {
    tipo: 'card.saiu_da_etapa',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [ETAPA],
  },
  {
    tipo: 'card.ganho',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [{ nome: 'funil_id', peca: 'funil', obrigatorio: false }],
  },
  {
    tipo: 'card.perdido',
    grupo: 'CARD',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [{ nome: 'funil_id', peca: 'funil', obrigatorio: false }],
  },
  {
    tipo: 'card.parado',
    grupo: 'TEMPO',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [ETAPA, DIAS],
    aviso: 'AVISO_PARADO',
  },
  {
    tipo: 'card.data',
    grupo: 'TEMPO',
    alvo: 'card',
    novo: true,
    crm: true,
    parametros: [
      { nome: 'campo', peca: 'campo_data_card', obrigatorio: true },
      DIAS,
      { nome: 'quando', peca: 'antes_depois', obrigatorio: true },
      HORA,
    ],
  },
  {
    tipo: 'contato.data',
    grupo: 'TEMPO',
    alvo: 'contato',
    novo: true,
    parametros: [
      { nome: 'campo', peca: 'campo_data_contato', obrigatorio: true },
      DIAS,
      { nome: 'quando', peca: 'antes_depois', obrigatorio: true },
      HORA,
    ],
  },
  {
    tipo: 'recorrente',
    grupo: 'TEMPO',
    alvo: 'card',
    novo: true,
    parametros: [
      { nome: 'frequencia', peca: 'frequencia', obrigatorio: true },
      { nome: 'dia', peca: 'dia', obrigatorio: true },
      HORA,
      { nome: 'alvo', peca: 'alvo_recorrente', obrigatorio: true },
    ],
  },
  {
    tipo: 'reuniao.marcada',
    grupo: 'REUNIAO',
    alvo: 'card',
    novo: true,
    crm: true,
  },
  {
    tipo: 'reuniao.remarcada',
    grupo: 'REUNIAO',
    alvo: 'card',
    novo: true,
    crm: true,
  },
  {
    tipo: 'reuniao.cancelada',
    grupo: 'REUNIAO',
    alvo: 'card',
    novo: true,
    crm: true,
  },
].map(item => ({
  ...item,
  frase: item.novo
    ? `${G}.TIPOS.${item.tipo.replace('.', '_').toUpperCase()}`
    : `AUTOMACAO_LIVRE.GATILHOS.${item.tipo.replace('.', '_').toUpperCase()}`,
  parametros: item.parametros || [],
}));

export const gatilhoDe = tipo => GATILHOS.find(item => item.tipo === tipo);

// O catálogo de hoje com os gatilhos novos. Os de card só para quem pode
// mexer no funil e com o CRM ligado; o servidor recusa o resto ao salvar.
export const comGatilhosNovos = (catalogo, { podeFunil }) =>
  catalogo && {
    ...catalogo,
    gatilhos: GATILHOS.filter(item => !item.crm || podeFunil),
  };

// O passo webhook (seção 7.1 do desenho), com a URL e os campos que saem.
export const PASSO_WEBHOOK = {
  tipo: 'webhook',
  grupo: 'INTEGRACAO',
  frase: `${G}.WEBHOOK.PASSO`,
  campos: [
    {
      nome: 'url',
      peca: 'url_do_webhook',
      obrigatorio: true,
      rotulo: `${G}.WEBHOOK.URL`,
    },
    {
      nome: 'campos',
      peca: 'campos_que_saem',
      obrigatorio: true,
      rotulo: `${G}.WEBHOOK.CAMPOS`,
    },
  ],
};

export const CAMPOS_QUE_SAEM = [
  'card.titulo',
  'card.valor',
  'card.etapa_id',
  'contato.nome',
  'contato.email',
  'contato.telefone',
  'conversa.id',
];

// "https://n8n.exemplo.com/webhook/abc?token=x" => "https://n8n.exemplo.com/…".
// É o que vê quem não tem a chave de integração.
export const mascararUrl = url => {
  try {
    return `${new URL(url).origin}/…`;
  } catch {
    return '…';
  }
};

const agora = Date.now();
const horasAtras = horas => new Date(agora - horas * 3600 * 1000).toISOString();
const diasDepois = dias => new Date(agora + dias * 86400 * 1000).toISOString();

// "Automações desta etapa": as antigas (CrmStageAutomation) e as novas que
// começam nesta etapa.
export const automacoesDaEtapa = stage => ({
  antigas: [
    {
      id: 'a1',
      nome: 'Criar retorno de 2 dias',
      gatilho: 'on_enter',
      ligada: true,
    },
  ],
  novas: [
    {
      id: 101,
      nome: `Orçamento parado em ${stage?.name || 'Orçamento enviado'}`,
      gatilho: { tipo: 'card.parado', etapa_id: stage?.id, dias: 3 },
      ligada: true,
      rodando: 4,
    },
    {
      id: 102,
      nome: 'Boas-vindas ao entrar',
      gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: stage?.id },
      ligada: false,
      rodando: 0,
    },
  ],
});

// "Automações deste cartão": o que está rodando e o histórico em frases.
export const automacoesDoCard = () => ({
  rodando: [
    {
      execucao_id: 9001,
      automacao_id: 101,
      nome: 'Orçamento parado em Orçamento enviado',
      passo: 'Esperar 2 dias',
      ate: diasDepois(2),
    },
  ],
  historico: [
    {
      em: horasAtras(30),
      frase: `${G}.CARD.HIST_ENTROU`,
      args: { etapa: 'Orçamento enviado' },
    },
    { em: horasAtras(29), frase: `${G}.CARD.HIST_MENSAGEM`, args: {} },
    { em: horasAtras(28), frase: `${G}.CARD.HIST_RETORNO`, args: { dias: 5 } },
    {
      em: horasAtras(2),
      frase: `${G}.CARD.HIST_WEBHOOK`,
      args: { host: 'n8n.exemplo.com', codigo: 200 },
    },
  ],
});
