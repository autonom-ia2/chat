import { DIA_EM_MS } from '../fonte/grupos';

// #2894 — "Mais filtros" da lista de pessoas: empresa, etiqueta, cidade e
// quando chegou. Vazio ('') quer dizer "qualquer".
export const FILTROS_VAZIOS = Object.freeze({
  empresa: '',
  etiqueta: '',
  cidade: '',
  chegouEm: '',
});

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

export const pessoaPassaNosFiltros = (
  pessoa,
  filtros = {},
  agora = Date.now()
) => {
  const { empresa, etiqueta, cidade, chegouEm } = filtros;
  if (preenchido(empresa) && !mesmaEmpresa(pessoa, empresa)) return false;
  if (preenchido(etiqueta) && !(pessoa.labels || []).includes(etiqueta)) {
    return false;
  }
  if (preenchido(cidade) && pessoa.additional_attributes?.city !== cidade) {
    return false;
  }
  return !preenchido(chegouEm) || chegouNoPeriodo(pessoa, chegouEm, agora);
};
