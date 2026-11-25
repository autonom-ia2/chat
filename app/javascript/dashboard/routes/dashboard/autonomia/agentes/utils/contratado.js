import { MAX_NOME, MAX_SOBRE } from '../constants/contratados';

// #3211 — a recusa do servidor no agente contratado (Tarefa 21, R14): 422 { error, code, campo }. A tela mostra o
// texto do i18n pelo `code` e destaca o `campo` (nulo = o formulário todo, como no `indisponivel`). Código que a tela
// não conhece: o texto do servidor; sem resposta (rede, 5xx): "tente de novo".
const TEXTO_DO_CODIGO = {
  marcador: t => t('AGENTS.CONTRATADOS.ERRO.MARCADOR'),
  indisponivel: t => t('AGENTS.CONTRATADOS.ERRO.INDISPONIVEL'),
  nome_agente: t =>
    t('AGENTS.CONTRATADOS.ERRO.NOME_AGENTE', { maximo: MAX_NOME }),
  nome_corretora: t =>
    t('AGENTS.CONTRATADOS.ERRO.NOME_CORRETORA', { maximo: MAX_NOME }),
  sobre_corretora: t =>
    t('AGENTS.CONTRATADOS.ERRO.SOBRE_CORRETORA', { maximo: MAX_SOBRE }),
  acesso_incompleto: t => t('AGENTS.CONTRATADOS.ERRO.ACESSO_INCOMPLETO'),
};

const STATUS_RECUSA = 422;

// -> { campo, texto, code }: `campo` é o nome que o servidor usa ('nome_corretora', 'senha'...), ou null.
export const erroDoContratado = (t, erro) => {
  const generico = t('AGENTS.CONTRATADOS.ERRO.GENERICO');
  const resposta = erro?.response;
  if (resposta?.status !== STATUS_RECUSA) {
    return { campo: null, texto: generico, code: null };
  }
  const { code = null, campo = null, error = '' } = resposta.data || {};
  const doCodigo = TEXTO_DO_CODIGO[code];
  const texto = doCodigo ? doCodigo(t) : error || generico;
  return { campo, texto, code };
};
