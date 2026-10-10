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

// Celular de exemplo da etapa Conte e perguntas prontas do teste (protótipo DATA.models): "Do meu
// jeito" usa as do primeiro modelo. As chaves ficam em AGENTS.JORNADA.MODELOS.<I18N> e
// AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.<CHAVE>.
const PERGUNTAS = {
  support: ['QUANTO_CUSTA', 'SABADO', 'PESSOA'],
  sdr: ['PEDIDO', 'DESCONTO', 'PESSOA'],
  reception: ['AJUDA', 'TROCAR', 'PESSOA'],
};

export const perguntasDeTeste = modelo =>
  PERGUNTAS[modelo] || PERGUNTAS.support;

export const exemploDoModelo = modelo =>
  (MODELOS.find(item => item.chave === modelo) || MODELOS[0]).i18n;

// "Ideias para começar" (DECISOES.md item 3): só no primeiro turno, preenchem o campo e a pessoa pode
// editar. Não respondem pergunta nenhuma da IA. "Do meu jeito" não tem: a pessoa conta com as
// palavras dela (o campo traz um exemplo).
export const IDEIAS_PARA_COMECAR = ['ROUPAS', 'DOCES', 'ESTETICA', 'OFICINA'];

// Arquivo da base: mesmo teto do backend (Source::MAX_FILE_BYTES, 25 MB).
export const MAX_ARQUIVO_BYTES = 25 * 1024 * 1024;
