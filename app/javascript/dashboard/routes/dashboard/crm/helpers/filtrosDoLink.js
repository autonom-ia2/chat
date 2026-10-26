// #1883 — filtros que chegam pelo link (os "Ver" do Números). Cada parâmetro é o
// nome do filtro que a tela já tem: no Kanban e na Lista, o mesmo da API; no Meu
// dia, o do painel "Mostrar". Valor que a tela não oferece é ignorado, nunca vira
// filtro escondido.
import {
  CRM_CAMPAIGN_QUERY,
  campaignSourceIdsFromQuery,
} from 'dashboard/components-next/CampaignResult/resultMetrics';
import { ORDEM_DOS_TIPOS } from '../components/calendario/itensDoCalendario';

const EU = 'me';
const DIAS_PARADO = ['3', '7', '14', '30'];
const RESPONSAVEIS = ['agent', 'bot', 'none'];
const RESULTADOS = ['open', 'won', 'lost', 'resolved', 'cancelled', 'archived'];
const FECHADO_EM = ['this_month'];
// Retornos: o mesmo filtro "Retorno" do Kanban e da Lista (#1883, opção 2 do Rodrigo).
const RETORNOS = ['none', 'pending', 'overdue'];
const QUEM = ['todos', 'meus'];

export const CHAVES_DO_LINK = [
  'owner_id',
  'stale_days',
  'responsible_kind',
  'result',
  'closed_in',
  'follow_up_status',
  CRM_CAMPAIGN_QUERY,
  'origem',
  'anuncio',
  'entrou_em',
];
export const CHAVES_DO_MEU_DIA = ['quem', 'tipos', 'funil'];

const idPositivo = valor => {
  const numero = Number(valor);
  return Number.isInteger(numero) && numero > 0 ? numero : null;
};

const dono = (valor, currentUserId) =>
  valor === EU ? idPositivo(currentUserId) : idPositivo(valor);

const daLista = (lista, valor) => (lista.includes(valor) ? valor : null);

// Números › Origens (#2001, F6). `result=todos` abre a Lista em "Todos"
// (quem entrou e quem já fechou); `anuncio` é o id do anúncio (só dígitos).
const ORIGENS = ['anuncio_meta', 'google', 'site', 'direto', 'outras'];
const TODOS = 'todos';
const ANUNCIO_MAX = 64;
const anuncioDoLink = valor =>
  typeof valor === 'string' &&
  valor.length > 0 &&
  valor.length <= ANUNCIO_MAX &&
  [...valor].every(c => c >= '0' && c <= '9')
    ? valor
    : null;
// Um mês AAAA-MM (Números › Origens, decisão 1: entrou ou fechou no mês).
const mesDoLink = valor => {
  if (typeof valor !== 'string' || valor.length !== 7 || valor[4] !== '-')
    return null;
  const digitos = [...valor.slice(0, 4), ...valor.slice(5)];
  const mes = Number(valor.slice(5));
  return digitos.every(c => c >= '0' && c <= '9') && mes >= 1 && mes <= 12
    ? valor
    : null;
};
const resultadoDoLink = valor =>
  valor === TODOS ? '' : daLista(RESULTADOS, valor);

const semVazios = filtro => {
  const cheio = Object.fromEntries(
    Object.entries(filtro).filter(([, valor]) =>
      Array.isArray(valor) ? valor.length : valor !== null
    )
  );
  return Object.keys(cheio).length ? cheio : null;
};

export const filtrosDoLink = (query = {}, { currentUserId } = {}) =>
  semVazios({
    ownerId: query.owner_id ? dono(query.owner_id, currentUserId) : null,
    staleDays: daLista(DIAS_PARADO, query.stale_days),
    responsibleKind: daLista(RESPONSAVEIS, query.responsible_kind),
    result: resultadoDoLink(query.result),
    closedIn: daLista(FECHADO_EM, query.closed_in),
    origem: daLista(ORIGENS, query.origem),
    anuncio: anuncioDoLink(query.anuncio),
    entrouEm: mesDoLink(query.entrou_em),
    followUpStatus: daLista(RETORNOS, query.follow_up_status),
    campaignSourceIds: campaignSourceIdsFromQuery(query),
  });

const tiposDoLink = valor =>
  typeof valor === 'string'
    ? valor.split(',').filter(tipo => ORDEM_DOS_TIPOS.includes(tipo))
    : [];

export const filtroDoMeuDiaPeloLink = (query = {}) =>
  semVazios({
    quem: daLista(QUEM, query.quem),
    tipos: tiposDoLink(query.tipos),
    funil: idPositivo(query.funil) ? String(query.funil) : null,
  });

export const semChaves = (query, chaves) =>
  Object.fromEntries(
    Object.entries(query).filter(([chave]) => !chaves.includes(chave))
  );
