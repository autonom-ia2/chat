// #2896 — o servidor não aceitou o valor que a pessoa escreveu para consertar
// uma linha (422 `valor_invalido`) e disse o motivo. Aqui o motivo vira a chave
// da frase que a própria linha mostra. Os motivos são os códigos que a leitura
// da planilha já usa (o servidor confere com os mesmos leitores):
//   telefone     — blank_phone_number, invalid_brazilian_mobile_number,
//                  formula_phone_number;
//   e-mail       — blank_email, invalid_email;
//   nome         — blank_name, formula_detected;
//   sem contato  — missing_contact (e os de telefone e de e-mail);
//   repetida     — a linha escolhida que o servidor não conhece
//                  (`linha_desconhecida`) não chega aqui: é tela desatualizada, e
//                  a tela lê a leitura de novo (fonte/trazerTraducao.js);
//   qualquer um  — muito_longo.
// O motivo é sempre do valor que a pessoa escreveu: quando o valor vale e a
// linha ainda tem outro problema, o servidor não recusa (devolve esse outro
// problema, e o cartão da linha muda).
// `planilha_apagada` não é motivo do valor: é a recusa do conserto inteiro, que
// a tela também diz na linha (trazer/useTrazerLista.js).
// `nao_salvou` também não é do valor, nem vem do servidor: é a escrita que
// falhou sem ele recusar nada (ele caiu, ou a rede caiu). A linha diz que não
// conseguiu salvar, sem culpar o que a pessoa escreveu.
// Motivo do servidor que a tela não conhece cai na frase do campo (telefone,
// e-mail ou nome); linha sem campo, na frase da linha. É só uma tabela de
// códigos: nenhum texto de pessoa é interpretado.
const BASE = 'RELACIONAMENTOS_TRAZER.PRECISAM.RECUSA';

const TELEFONE = `${BASE}.TELEFONE`;
const EMAIL = `${BASE}.EMAIL`;
const FORMULA = `${BASE}.FORMULA`;
const FRASE_DA_LINHA = `${BASE}.CAMPO.LINHA`;

export const MOTIVO_PLANILHA_APAGADA = 'planilha_apagada';
export const MOTIVO_NAO_SALVOU = 'nao_salvou';
export const MOTIVO_MUITO_LONGO = 'muito_longo';
export const FRASE_MUITO_LONGO = 'RELACIONAMENTOS_TRAZER.ERROS.MUITO_LONGO';

const FRASE_DO_MOTIVO = new Map([
  ['invalid_brazilian_mobile_number', TELEFONE],
  ['blank_phone_number', TELEFONE],
  ['formula_phone_number', FORMULA],
  ['invalid_email', EMAIL],
  ['blank_email', EMAIL],
  ['blank_name', `${BASE}.NOME`],
  ['formula_detected', FORMULA],
  ['missing_contact', `${BASE}.CONTATO`],
  [MOTIVO_MUITO_LONGO, FRASE_MUITO_LONGO],
  [MOTIVO_PLANILHA_APAGADA, 'RELACIONAMENTOS_TRAZER.PRECISAM.PLANILHA_APAGADA'],
  [MOTIVO_NAO_SALVOU, FRASE_DA_LINHA],
]);

const FRASE_DO_CAMPO = new Map([
  ['telefone', `${BASE}.CAMPO.TELEFONE`],
  ['email', `${BASE}.CAMPO.EMAIL`],
  ['nome', `${BASE}.CAMPO.NOME`],
]);

export const chaveDaRecusa = (campo, motivo) =>
  FRASE_DO_MOTIVO.get(motivo) ?? FRASE_DO_CAMPO.get(campo) ?? FRASE_DA_LINHA;
