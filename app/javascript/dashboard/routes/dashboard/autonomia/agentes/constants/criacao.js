import { MODELOS, MODELO_DO_MEU_JEITO } from './modelos';

// #1181 PR2 — a criação nova (Conte · Confira · Comece · Pronto). A rota é a mesma do Construtor
// (autonomia_agents_builder); a página lê da query o modelo (`?modelo=`, que a lista manda; `?type=`
// dos links antigos), o rascunho a continuar (`?agente=`) e a etapa (`?etapa=`).
export const ETAPA = {
  CONTE: 'conte',
  CONFIRA: 'confira',
  COMECE: 'comece',
  PRONTO: 'pronto',
};

const ETAPAS = Object.values(ETAPA);

const MODELOS_DE_CRIACAO = [
  ...MODELOS.map(modelo => modelo.chave),
  MODELO_DO_MEU_JEITO,
];

const texto = valor => (typeof valor === 'string' ? valor : '');

export const modeloDaQuery = (query = {}) => {
  const pedido = texto(query.modelo) || texto(query.type);
  return MODELOS_DE_CRIACAO.includes(pedido) ? pedido : MODELO_DO_MEU_JEITO;
};

// Depois que o rascunho existe a query só tem `?agente=`: o modelo vem do agent_type dele (F5).
export const modeloDoTipo = (tipo, padrao = MODELO_DO_MEU_JEITO) =>
  MODELOS_DE_CRIACAO.includes(tipo) ? tipo : padrao;

export const idDaQuery = (query = {}) => {
  const id = Number(texto(query.agente));
  return Number.isInteger(id) && id > 0 ? id : null;
};

export const etapaDaQuery = (query = {}) =>
  ETAPAS.includes(query.etapa) ? query.etapa : ETAPA.CONTE;

// #1494 — Copiloto da equipe: a lista manda `?atuacao=interno` e a conversa abre com
// `actuation: 'internal'` (ajuda a equipe dentro das conversas, nunca fala com cliente). Qualquer
// outro valor é o agente de sempre, que atende clientes. Depois que o rascunho existe, a query só
// tem `?agente=` e a atuação vem do próprio agente (F5).
export const ATUACAO = { EXTERNA: 'external', INTERNA: 'internal' };
export const ATUACAO_INTERNA_NA_QUERY = 'interno';

export const atuacaoDaQuery = (query = {}) =>
  query.atuacao === ATUACAO_INTERNA_NA_QUERY
    ? ATUACAO.INTERNA
    : ATUACAO.EXTERNA;

// Celular de exemplo da etapa Conte e perguntas prontas do teste (protótipo DATA.models): "Do meu
// jeito" usa as do primeiro modelo. As chaves ficam em AGENTS.JORNADA.MODELOS.<I18N> e
// AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.<CHAVE>.
const PERGUNTAS = {
  support: ['QUANTO_CUSTA', 'SABADO', 'PESSOA'],
  sdr: ['PEDIDO', 'DESCONTO', 'PESSOA'],
  reception: ['AJUDA', 'TROCAR', 'PESSOA'],
};

// O copiloto é testado como alguém da equipe pediria ajuda (o teste não tem uma conversa aberta,
// então as perguntas se explicam sozinhas).
const PERGUNTAS_DA_EQUIPE = ['COMO_RESPONDO', 'PROXIMO_PASSO', 'RASCUNHO'];

// Tema 14 (#1434) — o ajudante é testado como o agente principal o consultaria.
const PERGUNTAS_DO_AJUDANTE = [
  'AJUDANTE_O_QUE_SABE',
  'AJUDANTE_CLIENTE',
  'AJUDANTE_NAO_SABE',
];

export const perguntasDeTeste = (modelo, interno = false, ajudante = false) => {
  if (ajudante) return PERGUNTAS_DO_AJUDANTE;
  if (interno) return PERGUNTAS_DA_EQUIPE;
  return PERGUNTAS[modelo] || PERGUNTAS.support;
};

export const exemploDoModelo = modelo =>
  (MODELOS.find(item => item.chave === modelo) || MODELOS[0]).i18n;

// "Ideias para começar" (DECISOES.md item 3): só no primeiro turno, preenchem o campo e a pessoa pode
// editar. Não respondem pergunta nenhuma da IA. "Do meu jeito" não tem: a pessoa conta com as
// palavras dela (o campo traz um exemplo).
export const IDEIAS_PARA_COMECAR = ['ROUPAS', 'DOCES', 'ESTETICA', 'OFICINA'];

// Arquivo da base: mesmo teto do backend (Source::MAX_FILE_BYTES, 25 MB).
export const MAX_ARQUIVO_BYTES = 25 * 1024 * 1024;

// #1433 (tema 13) — agente da equipe: a página "Criar agente" manda `?papel=area` (só com a Fase 2). A
// conversa é a de sempre; no Comece ele escolhe canais que já têm principal e entra como área. A
// marca fica na query depois do rascunho (junto de `?agente=`), para o F5 continuar no mesmo papel.
export const PAPEL_AREA_NA_QUERY = 'area';
// Tema 14 (#1434) — "Ajuda outros agentes" (`?papel=ajudante`, só com a Fase 2). A conversa abre com
// `papel: 'ajudante'` (o agente nasce interno e com a marca de origem) e a marca fica na query, como a do
// agente da equipe, para o F5 continuar no mesmo papel.
export const PAPEL_AJUDANTE_NA_QUERY = 'ajudante';
const PAPEIS_NA_QUERY = [PAPEL_AREA_NA_QUERY, PAPEL_AJUDANTE_NA_QUERY];

export const papelDaQuery = (query = {}) =>
  PAPEIS_NA_QUERY.includes(query.papel) ? query.papel : null;

// #1433 — as caixas que o agente da equipe escolheu no começo (`?caixas=10,11`), antes da conversa. Ficam
// na URL até ele começar a trabalhar (F5 não pergunta de novo). Ids inválidos são ignorados.
const idsDoTexto = valor =>
  texto(valor)
    .split(',')
    .map(Number)
    .filter(id => Number.isInteger(id) && id > 0);

export const caixasDaQuery = (query = {}) => idsDoTexto(query.caixas);

export const caixasNaQuery = ids => ids.join(',');

// Tema 14 — quem o ajudante vai ajudar (`?ajuda=3,4`) e "quando chamar" (`?quando=`), escolhidos antes da
// conversa. Ficam na URL até ele começar a ajudar (F5 não pergunta de novo).
export const principaisDaQuery = (query = {}) => idsDoTexto(query.ajuda);

export const quandoDaQuery = (query = {}) => texto(query.quando).trim();
