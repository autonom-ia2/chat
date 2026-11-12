// #2896, Fatia 2 — a frase de cada linha que precisa da pessoa, pela chave do
// catálogo. O servidor diz o `tipo` do problema e, na linha aberta, pode dizer
// também o `motivo` (os mesmos códigos da recusa do conserto,
// trazer/recusaDoConserto.js). Com o motivo, a frase é a dele: o nome que é uma
// fórmula não é "falta o nome". Motivo sem frase própria fica com a do tipo.
// O tipo `formula` é a linha que a tela não conserta (a fórmula está numa
// célula que a pessoa não escreve aqui, dita em `campo`): a frase diz onde está
// e o que fazer. A linha guardada com o valor que a pessoa consertou
// (`corrigido`) mostra esse valor, e não mais o problema; a guardada sem ele (a
// repetida com que a pessoa ficou) e a deixada de fora continuam com a frase do
// problema. É só uma tabela de códigos do servidor: nenhum texto de pessoa é
// interpretado.
import { SITUACAO_DO_PROBLEMA } from './contagem';

const BASE = 'RELACIONAMENTOS_TRAZER.PRECISAM.PROBLEMA';

export const TIPO_FORMULA = 'formula';
const FRASE_DA_RESOLVIDA = 'RELACIONAMENTOS_TRAZER.PRECISAM.RESOLVIDA';

const FRASE_DO_TIPO = new Map([
  ['telefone', `${BASE}.TELEFONE`],
  ['email', `${BASE}.EMAIL`],
  ['nome', `${BASE}.NOME`],
  ['duplicada', `${BASE}.DUPLICADA`],
  ['sem_contato', `${BASE}.SEM_CONTATO`],
]);

const FRASE_DO_MOTIVO = new Map([
  [
    'telefone',
    new Map([
      ['blank_phone_number', `${BASE}.TELEFONE_VAZIO`],
      ['formula_phone_number', `${BASE}.TELEFONE_FORMULA`],
      ['formula_detected', `${BASE}.TELEFONE_FORMULA`],
    ]),
  ],
  [
    'email',
    new Map([
      ['blank_email', `${BASE}.EMAIL_VAZIO`],
      ['formula_detected', `${BASE}.EMAIL_FORMULA`],
    ]),
  ],
  ['nome', new Map([['formula_detected', `${BASE}.NOME_FORMULA`]])],
]);

// O campo da fórmula, no nome que a tela já dá a ele.
const NOME_DO_CAMPO = new Map([
  ['empresa', 'RELACIONAMENTOS_TRAZER.DESTINOS.EMPRESA'],
]);

export const chaveDoCampoComFormula = problema =>
  NOME_DO_CAMPO.get(problema.campo) ?? '';

const aberto = problema => problema.estado === SITUACAO_DO_PROBLEMA.ABERTO;
const resolvida = problema =>
  problema.estado === SITUACAO_DO_PROBLEMA.GUARDADO &&
  Boolean(problema.corrigido);

const fraseDaFormula = problema => {
  if (!aberto(problema)) return `${BASE}.FORMULA_RESUMO`;
  return chaveDoCampoComFormula(problema)
    ? `${BASE}.FORMULA`
    : `${BASE}.FORMULA_SEM_CAMPO`;
};

export const chaveDoTexto = problema => {
  if (resolvida(problema)) return FRASE_DA_RESOLVIDA;
  if (problema.tipo === TIPO_FORMULA) return fraseDaFormula(problema);
  const doMotivo = aberto(problema)
    ? FRASE_DO_MOTIVO.get(problema.tipo)?.get(problema.motivo)
    : undefined;
  return doMotivo ?? FRASE_DO_TIPO.get(problema.tipo);
};
