import { DIA_EM_MS } from '../fonte/grupos';
import { diasSemComprar } from '../fonte/gruposDeCompra';

// #2894 — "Mais filtros" da lista de pessoas: empresa, etiqueta, cidade e
// quando chegou. Vazio ('') quer dizer "qualquer".
export const FILTROS_VAZIOS = Object.freeze({
  empresa: '',
  etiqueta: '',
  cidade: '',
  chegouEm: '',
  // #3097 — compras: já comprou, nunca comprou ou comprou nos últimos N dias
  // (`ultimos_30`...); totalAcima: o total comprado, em reais, acima de N.
  compras: '',
  totalAcima: '',
  // #3100 — o cartão fidelidade: perto do prêmio ou cartão completo. Só o
  // servidor sabe o saldo: a lista da demonstração não filtra por ele.
  fidelidade: '',
});

export const FIDELIDADE = { PERTO: 'perto', COMPLETO: 'completo' };
// O valor que chega pela URL (?fidelidade=perto), ou vazio se não for um deles.
export const fidelidadeValida = valor =>
  Object.values(FIDELIDADE).includes(valor) ? valor : '';

export const COMPRAS = {
  JA_COMPROU: 'ja_comprou',
  NUNCA: 'nunca',
  ULTIMOS_30: 'ultimos_30',
  ULTIMOS_90: 'ultimos_90',
  ULTIMOS_180: 'ultimos_180',
};
export const DIAS_DAS_COMPRAS = {
  [COMPRAS.ULTIMOS_30]: 30,
  [COMPRAS.ULTIMOS_90]: 90,
  [COMPRAS.ULTIMOS_180]: 180,
};
export const TOTAIS_ACIMA = [100, 250, 500, 1000, 5000];

export const PERIODOS_DE_CHEGADA = {
  ULTIMOS_7: 'ultimos_7',
  ULTIMOS_30: 'ultimos_30',
  ULTIMOS_90: 'ultimos_90',
};

const DIAS_DO_PERIODO = {
  [PERIODOS_DE_CHEGADA.ULTIMOS_7]: 7,
  [PERIODOS_DE_CHEGADA.ULTIMOS_30]: 30,
  [PERIODOS_DE_CHEGADA.ULTIMOS_90]: 90,
};

export const preenchido = valor =>
  valor !== '' && valor !== null && valor !== undefined;

export const contarFiltros = (filtros = {}) =>
  Object.keys(FILTROS_VAZIOS).filter(chave => preenchido(filtros[chave]))
    .length;

const mesmaEmpresa = (pessoa, empresa) =>
  String(pessoa.company_id) === String(empresa);

const chegouNoPeriodo = (pessoa, periodo, agora) => {
  const dias = DIAS_DO_PERIODO[periodo];
  if (!dias) return true;
  return pessoa.created_at * 1000 >= agora - dias * DIA_EM_MS;
};

const totalEmReais = compras =>
  (compras?.por_moeda || []).find(({ moeda }) => moeda === 'BRL')?.total ?? 0;

const passaNasCompras = (compras, filtro, agora) => {
  if (!preenchido(filtro)) return true;
  const comprou = Boolean(compras?.quantas);
  if (filtro === COMPRAS.NUNCA) return !comprou;
  if (filtro === COMPRAS.JA_COMPROU) return comprou;
  return comprou && diasSemComprar(compras, agora) <= DIAS_DAS_COMPRAS[filtro];
};

export const pessoaPassaNosFiltros = (
  pessoa,
  filtros = {},
  agora = Date.now()
) => {
  const { empresa, etiqueta, cidade, chegouEm, compras, totalAcima } = filtros;
  if (!passaNasCompras(pessoa.compras, compras, agora)) return false;
  if (
    preenchido(totalAcima) &&
    !(totalEmReais(pessoa.compras) > Number(totalAcima))
  ) {
    return false;
  }
  if (preenchido(empresa) && !mesmaEmpresa(pessoa, empresa)) return false;
  if (preenchido(etiqueta) && !(pessoa.labels || []).includes(etiqueta)) {
    return false;
  }
  if (preenchido(cidade) && pessoa.additional_attributes?.city !== cidade) {
    return false;
  }
  return !preenchido(chegouEm) || chegouNoPeriodo(pessoa, chegouEm, agora);
};

// #3078 — "Mais filtros" da aba Empresas: cidade e quando chegou (a lista
// antiga de Empresas não filtrava; são os dois da aba Pessoas que existem na
// empresa). Os outros não se aplicam e não vão ao servidor.
export const FILTROS_DAS_EMPRESAS = Object.freeze(['cidade', 'chegouEm']);

export const empresaPassaNosFiltros = (
  empresa,
  filtros = {},
  agora = Date.now()
) => {
  const { cidade, chegouEm } = filtros;
  if (preenchido(cidade) && empresa.city !== cidade) return false;
  return !preenchido(chegouEm) || chegouNoPeriodo(empresa, chegouEm, agora);
};
