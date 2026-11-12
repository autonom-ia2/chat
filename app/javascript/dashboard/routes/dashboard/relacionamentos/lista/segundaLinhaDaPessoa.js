import { formatarTelefone } from './telefone';
import { falouHa } from './tempoRelativo';

// #2894 — as informações da segunda linha de uma pessoa, na ordem em que
// aparecem: telefone (ou "sem telefone"), empresa e quando falou. `t` é o
// tradutor da tela.
const LINHA = 'RELACIONAMENTOS.LISTA.LINHA';

const quandoFalou = (pessoa, agora, t) => {
  const quando = falouHa(pessoa.last_activity_at, agora);
  return quando.count === undefined
    ? t(quando.chave)
    : t(quando.chave, { count: quando.count }, quando.count);
};

export const segundaLinhaDaPessoa = (pessoa, agora, t) =>
  [
    formatarTelefone(pessoa.phone_number) || t(`${LINHA}.SEM_TELEFONE`),
    pessoa.additional_attributes?.company_name,
    quandoFalou(pessoa, agora, t),
  ].filter(Boolean);
