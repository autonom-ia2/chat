import { formatarTelefone } from './telefone';
import { falouHa } from './tempoRelativo';

// #2894 — as informações da segunda linha de uma pessoa, na ordem em que
// aparecem: telefone (ou "sem telefone"), quando falou e empresa (#3057). `t`
// é o tradutor da tela.
const LINHA = 'RELACIONAMENTOS.LISTA.LINHA';

const quandoFalou = (pessoa, agora, t) => {
  const quando = falouHa(pessoa.last_activity_at, agora);
  return quando.count === undefined
    ? t(quando.chave)
    : t(quando.chave, { count: quando.count }, quando.count);
};

// #3057 (revisão) — no celular o telefone fica numa linha e "Falou…" e a
// empresa na de baixo, a empresa cortada se não couber
// (components/lista/SegundaLinha.vue). Por isso "Falou…" vem antes da empresa.
export const segundaLinhaDaPessoa = (pessoa, agora, t) => {
  const empresa = pessoa.additional_attributes?.company_name;
  return [
    {
      texto:
        formatarTelefone(pessoa.phone_number) || t(`${LINHA}.SEM_TELEFONE`),
      sozinha: true,
    },
    quandoFalou(pessoa, agora, t),
    empresa && { texto: empresa, corta: true },
  ].filter(Boolean);
};
