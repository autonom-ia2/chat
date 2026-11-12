// #2897 — as recusas da carteira que têm nome. Quando o servidor recusa o que a
// tela pediu (422), a resposta traz só um código (`{ error: "<código>" }`), nunca
// o que a pessoa digitou. A fonte dá a essa falha o nome `RECUSADO` e guarda o
// código; a tela escolhe a frase do catálogo pelo código e, como ele, nunca
// repete o valor digitado.
export const RECUSADO = 'RECUSADO';
// O PDF passou do tamanho que a instalação aceita: a tela confere antes de
// enviar e o servidor responde o mesmo código.
export const ARQUIVO_GRANDE = 'arquivo_grande';

export const CODIGOS_DE_RECUSA = [
  'falta_numero',
  'falta_seguradora',
  'falta_termina',
  'termina_antes',
  'data_invalida',
  'valor_invalido',
  'tipo_desconhecido',
  'apolice_repetida',
  'ja_cancelado',
  'nao_cancelado',
  'arquivo_obrigatorio',
  'tipo',
  ARQUIVO_GRANDE,
  'sem_pdf',
  'pedido_invalido',
];

// O seguro mudou por outro caminho (outra pessoa, outra aba): o que a tela
// mostra já não vale, e ela relê o seguro depois de dizer o que houve.
const SEGURO_JA_MUDOU = ['ja_cancelado', 'nao_cancelado', 'sem_pdf'];

export const codigoDaRecusa = falha =>
  falha?.name === RECUSADO && CODIGOS_DE_RECUSA.includes(falha.codigo)
    ? falha.codigo
    : '';

export const seguroJaMudou = codigo => SEGURO_JA_MUDOU.includes(codigo);

// A chave da frase no catálogo; sem código conhecido, a frase de sempre de quem
// chamou (`padrao`).
export const chaveDaRecusa = (codigo, padrao) =>
  CODIGOS_DE_RECUSA.includes(codigo)
    ? `RELACIONAMENTOS_CARTEIRA.RECUSAS.${codigo.toUpperCase()}`
    : padrao;
