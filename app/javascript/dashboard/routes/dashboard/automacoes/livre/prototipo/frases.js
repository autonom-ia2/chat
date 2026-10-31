// #2414 F0 — a receita lida em frase. Cada tipo tem a sua frase no i18n
// (AUTOMACAO_LIVRE.PASSOS/GATILHOS/CONDICOES/...); os nomes (etapa, modelo,
// equipe, campo) vêm dos dados da conta.
import {
  ACOES_DA_PLATAFORMA,
  TIPOS_DE_PASSO,
  TIPOS_DE_GATILHO,
} from './catalogo';
import {
  CAIXAS,
  CAMPOS_DO_CARTAO,
  EQUIPES,
  ETAPAS,
  MODELOS_WHATSAPP,
} from './dados';

const P = 'AUTOMACAO_LIVRE';

const nomeEm = (lista, id) => lista.find(item => item.id === id)?.nome || '';

export const nomeDaEtapa = id => nomeEm(ETAPAS, id);
export const nomeDoModelo = id => nomeEm(MODELOS_WHATSAPP, id);
export const nomeDaEquipe = id => nomeEm(EQUIPES, id);
export const nomeDoCampo = id => nomeEm(CAMPOS_DO_CARTAO, id);
export const nomeDaCaixa = id => nomeEm(CAIXAS, id);
export const modeloPorId = id =>
  MODELOS_WHATSAPP.find(modelo => modelo.id === id) || null;

export const dinheiro = (valor, locale = 'pt-BR') =>
  new Intl.NumberFormat(locale, { style: 'currency', currency: 'BRL' }).format(
    valor
  );

// O i18n da conta vem como "pt_BR"; o Intl quer "pt-BR".
export const localeDoIntl = locale => (locale || 'pt_BR').split('_').join('-');

// "qui., 10:00": até quando algo espera (sempre nos próximos dias).
export const quando = (iso, locale) =>
  new Intl.DateTimeFormat(localeDoIntl(locale), {
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

// "sex., 30/10, 10:02": quando algo aconteceu.
export const quandoFoi = (iso, locale) =>
  new Intl.DateTimeFormat(localeDoIntl(locale), {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

const pessoa = (chave, t) => t(`${P}.PESSOAS.${chave.toUpperCase()}`);

const VARIAVEIS_FIXAS = {
  'contato.nome': 'CONTATO_NOME',
  'card.valor': 'CARD_VALOR',
  'card.responsavel': 'CARD_RESPONSAVEL',
};
const PREFIXO_CAMPO = 'card.campo.';

export const rotuloDaVariavel = (chave, t) => {
  if (chave.startsWith(PREFIXO_CAMPO))
    return nomeDoCampo(chave.slice(PREFIXO_CAMPO.length));
  return t(`${P}.VARIAVEIS.${VARIAVEIS_FIXAS[chave] || 'OUTRA'}`);
};

export const fraseDaCondicao = (condicao, t) => {
  const params = {
    etapa: nomeDaEtapa(condicao.etapa),
    valor: condicao.valor !== undefined ? dinheiro(condicao.valor) : '',
    caixa: nomeDaCaixa(condicao.caixa),
  };
  return t(`${P}.CONDICOES.${condicao.tipo.toUpperCase()}`, params);
};

export const fraseDoGatilho = (gatilho, t) => {
  if (!gatilho) return t(`${P}.GATILHOS.FALTA`);
  const params = {
    etapa: nomeDaEtapa(gatilho.etapa),
    campo: nomeDoCampo(gatilho.campo),
    n: gatilho.dias,
  };
  return t(
    `${P}.GATILHOS.${gatilho.tipo.toUpperCase()}`,
    params,
    gatilho.dias || 1
  );
};

export const tipoDeGatilhoExiste = tipo =>
  TIPOS_DE_GATILHO.some(item => item.tipo === tipo);

const fraseDaAcao = (passo, t) => {
  const acao = ACOES_DA_PLATAFORMA.find(item => item.chave === passo.acao);
  if (!acao || acao.semFrase) return t(`${P}.PLATAFORMA.AVANCADA`);
  return t(`${P}.PLATAFORMA.${acao.chave}`);
};

export const fraseDoPasso = (passo, t) => {
  if (passo.tipo === 'acao_plataforma') return fraseDaAcao(passo, t);
  if (!TIPOS_DE_PASSO[passo.tipo]) return t(`${P}.PLATAFORMA.AVANCADA`);
  const params = {
    etapa: nomeDaEtapa(passo.etapa),
    modelo: nomeDoModelo(passo.modelo),
    equipe: nomeDaEquipe(passo.equipe),
    para: passo.para ? pessoa(passo.para, t) : '',
    titulo: passo.titulo || '',
    motivo: passo.motivo || '',
    etiqueta: passo.etiqueta || '',
    pergunta: passo.pergunta || '',
    campos: (passo.campos || []).map(nomeDoCampo).join(', '),
    condicao: passo.condicao ? fraseDaCondicao(passo.condicao, t) : '',
    n: passo.dias,
  };
  const chave =
    passo.tipo === 'fechar_cartao'
      ? `FECHAR_${(passo.resultado || 'perdido').toUpperCase()}`
      : passo.tipo.toUpperCase();
  return t(`${P}.PASSOS.${chave}`, params, passo.dias || 1);
};

export const rotuloDoCaminho = (passo, caminho, t) => {
  if (caminho.chave === 'nenhuma') return t(`${P}.CAMINHOS.NENHUMA`);
  if (caminho.rotulo) return caminho.rotulo;
  return t(`${P}.CAMINHOS.${caminho.chave.toUpperCase()}`, { n: passo.dias });
};

export const fraseDaMeta = (meta, t) =>
  t(`${P}.METAS.${(meta?.tipo || 'nenhuma').toUpperCase()}`);

// Só as linhas preenchidas, na ordem em que a pessoa lê.
export const frasesDoFreio = (freio, t) =>
  [['nao_repetir_dias', 'NAO_REPETIR']]
    .filter(([campo]) => freio?.[campo])
    .map(([campo, chave]) =>
      t(`${P}.FREIO.${chave}`, { n: freio[campo] }, freio[campo])
    );

// Texto da mensagem com as variáveis trocadas por valores (ensaio) ou por
// colchetes com o nome (ex.: dentro de uma frase curta).
export const textoDaMensagem = (pedacos, valores, t) =>
  (pedacos || [])
    .map(pedaco => {
      if (typeof pedaco === 'string') return pedaco;
      const valor = valores?.[pedaco.$valor];
      return valor || `[${rotuloDaVariavel(pedaco.$valor, t)}]`;
    })
    .join('');
