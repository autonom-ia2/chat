// #3097 — os números das faixas de compra em palavras, para os nomes e as
// explicações dos grupos ("Sem comprar há 3 a 6 meses"). Conta redonda de 30
// dias vira mês; o resto fica em dias. `t` é o tradutor da tela.
const U = 'RELACIONAMENTOS_COMPRAS.UNIDADES';
const DIAS_NO_MES = 30;
const emMeses = dias => dias % DIAS_NO_MES === 0;

const prazo = (dias, t) =>
  emMeses(dias)
    ? t(`${U}.MESES`, { count: dias / DIAS_NO_MES }, dias / DIAS_NO_MES)
    : t(`${U}.DIAS`, { count: dias }, dias);

const entre = (de, ate, t) =>
  emMeses(de) && emMeses(ate)
    ? t(`${U}.ENTRE_MESES`, { de: de / DIAS_NO_MES, ate: ate / DIAS_NO_MES })
    : t(`${U}.ENTRE_DIAS`, { de, ate });

export const textosDasFaixas = (faixas, t) => ({
  campeao_compras: faixas.campeao_compras,
  campeao: prazo(faixas.campeao_dias, t),
  em_risco: prazo(faixas.em_risco_dias, t),
  perdido: prazo(faixas.perdido_dias, t),
  entre: entre(faixas.em_risco_dias, faixas.perdido_dias, t),
});
