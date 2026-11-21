import { formatarTelefone } from './telefone';
import { falouHa } from './tempoRelativo';
import { quandoComprou } from '../ficha/compras';
import { SEPARADOR } from '../components/comum/ponto';

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
// #3097 — com os grupos por compra (`porCompra`), o "Falou…" dá lugar à compra:
// "Comprou há 12 dias · 5 compras", ou "Nunca comprou". `idioma` é o do Intl.
const COMPRAS = 'RELACIONAMENTOS_COMPRAS.LISTA';
// A compra fica numa linha própria no celular (`sozinha`), para "· 5 compras"
// não cair sozinho na linha de baixo.
const daCompra = (compras, agora, t, idioma) => ({
  texto: compras?.quantas
    ? [
        t(`${COMPRAS}.COMPROU_HA`, {
          quando: quandoComprou(compras.ultima_em, agora, idioma),
        }),
        t(`${COMPRAS}.COMPRAS`, { count: compras.quantas }, compras.quantas),
      ].join(SEPARADOR)
    : t(`${COMPRAS}.NUNCA_COMPROU`),
  sozinha: true,
});

export const segundaLinhaDaPessoa = (
  pessoa,
  agora,
  t,
  { porCompra = false, idioma = 'pt-BR' } = {}
) => {
  const empresa = pessoa.additional_attributes?.company_name;
  return [
    {
      texto:
        formatarTelefone(pessoa.phone_number) || t(`${LINHA}.SEM_TELEFONE`),
      sozinha: true,
    },
    ...(porCompra
      ? [daCompra(pessoa.compras, agora, t, idioma)]
      : [quandoFalou(pessoa, agora, t)]),
    empresa && { texto: empresa, corta: true },
  ].filter(Boolean);
};
