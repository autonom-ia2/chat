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

// #3057 (revisão) — a empresa vem com `sozinha`: no celular ela desce para a
// última linha, cortada se não couber, e telefone e "Falou" ficam juntos
// (components/lista/SegundaLinha.vue).
export const segundaLinhaDaPessoa = (pessoa, agora, t) => {
  const empresa = pessoa.additional_attributes?.company_name;
  return [
    formatarTelefone(pessoa.phone_number) || t(`${LINHA}.SEM_TELEFONE`),
    empresa && { texto: empresa, sozinha: true },
    quandoFalou(pessoa, agora, t),
  ].filter(Boolean);
};
