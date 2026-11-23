import { attributeDate } from 'dashboard/helper/attributeDate';
import {
  RELACOES,
  chaveDoTexto,
} from 'dashboard/components-next/contato-relacao/relacaoDoContato';
import { opcoesDePais } from '../ficha/paises';

// #3168 — "Por outra informação", na gaveta "Mais filtros" da aba Pessoas: o
// catálogo das informações que dá para escolher, o "como" de cada tipo e a
// conta de cada linha (a condição). As chaves e os operadores são os de
// `contacts/filter` (lib/filters/filter_keys.yml, contactProvider.js), para o
// grupo guardado ser o mesmo `custom_filter` que a tela antiga lê.
//
// Uma condição: { id, chave, tipo, modelo, como, valor }. `chave` vazia é a
// linha que ainda não escolheu a informação: ela não vai para a busca.
// Funções puras: nada aqui muta o que recebe.

export const TIPOS = Object.freeze({
  TEXTO: 'texto',
  IGUAL: 'igual',
  LISTA: 'lista',
  NUMERO: 'numero',
  LINK: 'link',
  SIM_NAO: 'sim_nao',
  DATA: 'data',
  // A data de um campo da conta: também pode estar preenchida ou vazia.
  DATA_DA_CONTA: 'data_da_conta',
});

export const OPERADORES = Object.freeze({
  TEM: 'contains',
  NAO_TEM: 'does_not_contain',
  IGUAL: 'equal_to',
  DIFERENTE: 'not_equal_to',
  DEPOIS: 'is_greater_than',
  ANTES: 'is_less_than',
  HA_MAIS_DE_DIAS: 'days_before',
  PREENCHIDO: 'is_present',
  VAZIO: 'is_not_present',
});

// "Mostrar quem tem": todas as condições ou pelo menos uma.
export const JUNTAR = Object.freeze({ TODAS: 'todas', QUALQUER: 'qualquer' });

// Onde a informação mora no servidor (o `attribute_model` do payload).
export const MODELOS = Object.freeze({
  PADRAO: 'standard',
  ADICIONAL: 'additional',
  DA_CONTA: 'customAttributes',
});

const {
  TEM,
  NAO_TEM,
  IGUAL,
  DIFERENTE,
  DEPOIS,
  ANTES,
  HA_MAIS_DE_DIAS,
  PREENCHIDO,
  VAZIO,
} = OPERADORES;

const DE_DATA = [DEPOIS, ANTES, HA_MAIS_DE_DIAS];
export const COMO_DO_TIPO = Object.freeze({
  [TIPOS.TEXTO]: [TEM, NAO_TEM, IGUAL, DIFERENTE],
  [TIPOS.IGUAL]: [IGUAL, DIFERENTE],
  [TIPOS.LISTA]: [IGUAL, DIFERENTE],
  [TIPOS.NUMERO]: [IGUAL, DIFERENTE],
  [TIPOS.LINK]: [IGUAL, DIFERENTE],
  [TIPOS.SIM_NAO]: [IGUAL],
  [TIPOS.DATA]: DE_DATA,
  [TIPOS.DATA_DA_CONTA]: [...DE_DATA, PREENCHIDO, VAZIO],
});

// #3168 (diretor de arte) — a etiqueta, embaixo, só serve para "não tem": "tem
// a etiqueta" já está em cima, na escolha Etiqueta. Por isso a informação se
// chama "Não tem a etiqueta" e tem um "como" só.
const COMOS_PROPRIOS = { labels: [DIFERENTE] };
export const comosDa = ({ chave, tipo, modelo }) =>
  (modelo !== MODELOS.DA_CONTA && COMOS_PROPRIOS[chave]) ||
  COMO_DO_TIPO[tipo] ||
  [];
// Com um "como" só (Bloqueada, Não tem a etiqueta), a tela não pergunta "Como".
export const temUmComoSo = condicao => comosDa(condicao).length === 1;

const SEM_VALOR = [PREENCHIDO, VAZIO];
export const pedeValor = como => !SEM_VALOR.includes(como);

const ehData = tipo => tipo === TIPOS.DATA || tipo === TIPOS.DATA_DA_CONTA;

// O rótulo do "como" na tela (RELACIONAMENTOS.LISTA.CONDICOES.COMO.<chave>):
// no texto, "é igual a"; nos outros tipos, só "é".
const ROTULO_DO_COMO = {
  // "tem o texto", "não tem o texto" (#3168, diretor de arte).
  [TEM]: 'TEM',
  [NAO_TEM]: 'NAO_TEM',
  [DEPOIS]: 'DEPOIS',
  [ANTES]: 'ANTES',
  [HA_MAIS_DE_DIAS]: 'HA_MAIS_DE_DIAS',
  [PREENCHIDO]: 'PREENCHIDO',
  [VAZIO]: 'VAZIO',
};
export const rotuloDoComo = (tipo, como) => {
  if (ROTULO_DO_COMO[como]) return ROTULO_DO_COMO[como];
  if (tipo === TIPOS.TEXTO) return como === IGUAL ? 'IGUAL_A' : 'DIFERENTE_DE';
  return como === IGUAL ? 'E' : 'NAO_E';
};

// ---- o catálogo -----------------------------------------------------------

// As informações da pessoa, na ordem da tela, com as chaves de contactProvider.
// `opcoes` diz de onde vem a lista (países, etiquetas ou relação). Ficam de
// fora as que a gaveta já tem em cima (cidade, empresa, quando chegou) e o
// código da pessoa, que o leigo não conhece (#3168, diretor de arte).
const DA_PESSOA = [
  { chave: 'name', rotulo: 'NOME', tipo: TIPOS.TEXTO },
  { chave: 'email', rotulo: 'EMAIL', tipo: TIPOS.TEXTO },
  { chave: 'phone_number', rotulo: 'TELEFONE', tipo: TIPOS.TEXTO },
  {
    chave: 'country_code',
    rotulo: 'PAIS',
    tipo: TIPOS.LISTA,
    modelo: MODELOS.ADICIONAL,
    opcoes: 'paises',
  },
  { chave: 'last_activity_at', rotulo: 'ULTIMA_CONVERSA', tipo: TIPOS.DATA },
  { chave: 'blocked', rotulo: 'BLOQUEADA', tipo: TIPOS.SIM_NAO },
  {
    chave: 'labels',
    rotulo: 'NAO_TEM_ETIQUETA',
    tipo: TIPOS.LISTA,
    opcoes: 'etiquetas',
  },
  { chave: 'relacao', rotulo: 'RELACAO', tipo: TIPOS.LISTA, opcoes: 'relacao' },
];
// Campo da conta com a chave de uma informação da pessoa (inclusive as que
// estão em cima) não entra: repetiria a mesma informação.
export const CHAVES_DA_PESSOA = [
  ...DA_PESSOA.map(({ chave }) => chave),
  'city',
  'company_name',
  'created_at',
  'identifier',
];

// O tipo do campo da conta (attribute_display_type) na tela.
const TIPO_DO_CAMPO = {
  text: TIPOS.TEXTO,
  number: TIPOS.NUMERO,
  link: TIPOS.LINK,
  date: TIPOS.DATA_DA_CONTA,
  list: TIPOS.LISTA,
  checkbox: TIPOS.SIM_NAO,
};

const comoOpcao = valor => ({ value: valor, label: valor });

const opcoesDaPessoa = ({ t, idioma, etiquetas }) => ({
  paises: opcoesDePais(idioma, ''),
  etiquetas,
  relacao: RELACOES.map(relacao => ({
    value: relacao,
    label: t(chaveDoTexto(relacao, 'ROTULO')),
  })),
});

const CI = 'RELACIONAMENTOS.LISTA.CONDICOES.INFORMACOES';

// `definicoes`: os campos personalizados de contato da conta (snake_case, como
// o servidor manda). Campo com a chave de uma informação da pessoa fica de
// fora, como em buildAttributesFilterTypes. `comRelacao`: a conta tem a chave
// `contato_relacao`. `etiquetas`: [{ value, label }] da conta.
export const catalogoDeInformacoes = ({
  t,
  idioma,
  definicoes = [],
  comRelacao = false,
  etiquetas = [],
}) => {
  const listas = opcoesDaPessoa({ t, idioma, etiquetas });
  const daPessoa = DA_PESSOA.filter(
    item => comRelacao || item.chave !== 'relacao'
  ).map(({ chave, rotulo, tipo, modelo = MODELOS.PADRAO, opcoes }) => ({
    chave,
    rotulo: t(`${CI}.${rotulo}`),
    tipo,
    modelo,
    opcoes: opcoes ? listas[opcoes] : [],
  }));
  const daConta = definicoes
    .filter(definicao => !CHAVES_DA_PESSOA.includes(definicao.attribute_key))
    .map(definicao => ({
      chave: definicao.attribute_key,
      rotulo: definicao.attribute_display_name || definicao.attribute_key,
      tipo: TIPO_DO_CAMPO[definicao.attribute_display_type] ?? TIPOS.TEXTO,
      modelo: MODELOS.DA_CONTA,
      opcoes: (definicao.attribute_values ?? []).map(comoOpcao),
    }));
  return { daPessoa, daConta };
};

// ---- as linhas ------------------------------------------------------------

export const novaCondicao = id => ({
  id,
  chave: '',
  tipo: '',
  modelo: '',
  como: '',
  valor: '',
});

// O valor com que a linha nasce: "sim ou não" já vem em Sim.
const valorInicial = tipo => (tipo === TIPOS.SIM_NAO ? true : '');

export const comInformacao = (condicao, { chave, tipo, modelo }) => ({
  ...condicao,
  chave,
  tipo,
  modelo,
  como: comosDa({ chave, tipo, modelo })[0],
  valor: valorInicial(tipo),
});

// Trocar o "como" só apaga o valor quando o tipo de valor muda (a data vira
// número de dias, ou o contrário).
const tipoDoValor = como => (como === HA_MAIS_DE_DIAS ? 'dias' : 'outro');
export const comComo = (condicao, como) => ({
  ...condicao,
  como,
  valor:
    tipoDoValor(como) === tipoDoValor(condicao.como) && pedeValor(como)
      ? condicao.valor
      : valorInicial(condicao.tipo),
});

const vazio = valor => valor === '' || valor === null || valor === undefined;

// O que falta na linha, para a tela dizer (RELACIONAMENTOS.LISTA.CONDICOES.
// ERRO.<código>), ou '' quando ela está pronta (ou não escolheu informação).
export const erroDaCondicao = ({ chave, tipo, como, valor }) => {
  if (!chave || !pedeValor(como)) return '';
  if (como === HA_MAIS_DE_DIAS) return Number(valor) > 0 ? '' : 'FALTA_DIAS';
  if (ehData(tipo)) {
    if (vazio(valor)) return 'FALTA_DIA';
    return attributeDate(valor) ? '' : 'DATA_ERRADA';
  }
  if (!vazio(valor) && String(valor).trim() !== '') return '';
  return tipo === TIPOS.LISTA ? 'FALTA_ESCOLHA' : 'FALTA_TEXTO';
};

// As linhas que vão para a busca: com informação e sem nada faltando.
export const condicoesProntas = (condicoes = []) =>
  condicoes.filter(condicao => condicao.chave && !erroDaCondicao(condicao));

const valoresDoServidor = ({ como, valor }) => {
  if (!pedeValor(como)) return [];
  return [typeof valor === 'string' ? valor.trim() : valor];
};

// O payload de `contacts/filter` (o mesmo do filtro antigo, depois do
// filterQueryGenerator): cada linha com o `query_operator` que a liga à
// próxima; a última vai sem ele.
export const paraOServidor = (condicoes = [], juntar = JUNTAR.TODAS) => {
  const prontas = condicoesProntas(condicoes);
  const ligacao = juntar === JUNTAR.QUALQUER ? 'or' : 'and';
  return prontas.map((condicao, indice) => ({
    attribute_key: condicao.chave,
    filter_operator: condicao.como,
    values: valoresDoServidor(condicao),
    query_operator: indice < prontas.length - 1 ? ligacao : undefined,
    attribute_model: condicao.modelo || MODELOS.PADRAO,
    custom_attribute_type: '',
  }));
};
