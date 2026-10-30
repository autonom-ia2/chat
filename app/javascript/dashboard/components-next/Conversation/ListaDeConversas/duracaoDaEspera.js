// #2202 — quanto tempo alguém espera (linha 3 da lista), sem buraco entre as faixas:
// "há menos de 1 min", "há 1 min"… "há 59 min", "há 1 hora"… "há 23 horas",
// "há 1 dia"… "há 89 dias" e "há 3 meses" a partir de 90 dias.
// E a faixa de cor (decisão 6 do Rodrigo): até 15 min calma, até 2 h atenção (âmbar),
// até 7 dias urgente (vermelho) e, de 7 dias em diante, parada (cinza, "Sem resposta há").
const MINUTO = 60;
const HORA = 60 * MINUTO;
const DIA = 24 * HORA;
const DIAS_PARA_MESES = 90;
const DIAS_NO_MES = 30;

export const FAIXA = {
  CALMA: 'calma',
  ATENCAO: 'atencao',
  URGENTE: 'urgente',
  PARADA: 'parada',
};

export const LIMITE_ATENCAO = 15 * MINUTO;
export const LIMITE_URGENTE = 2 * HORA;
export const LIMITE_PARADA = 7 * DIA;

export const duracaoDaEspera = (segundos, t) => {
  const s = Math.max(0, Math.floor(segundos));
  if (s < MINUTO) return t('LISTA_DE_CONVERSAS.DURACAO.MENOS_DE_1_MIN');
  if (s < HORA) {
    return t('LISTA_DE_CONVERSAS.DURACAO.MIN', { n: Math.floor(s / MINUTO) });
  }
  if (s < DIA) {
    const n = Math.floor(s / HORA);
    return t('LISTA_DE_CONVERSAS.DURACAO.HORA', { n }, n);
  }
  const dias = Math.floor(s / DIA);
  if (dias < DIAS_PARA_MESES) {
    return t('LISTA_DE_CONVERSAS.DURACAO.DIA', { n: dias }, dias);
  }
  return t('LISTA_DE_CONVERSAS.DURACAO.MESES', {
    n: Math.floor(dias / DIAS_NO_MES),
  });
};

export const faixaDaEspera = segundos => {
  if (segundos < LIMITE_ATENCAO) return FAIXA.CALMA;
  if (segundos < LIMITE_URGENTE) return FAIXA.ATENCAO;
  if (segundos < LIMITE_PARADA) return FAIXA.URGENTE;
  return FAIXA.PARADA;
};
