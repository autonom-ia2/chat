// #2138 — a data "como se fala", no fuso da conta: "hoje às 16h", "ontem às 10h",
// "quinta às 14h", "25 de novembro às 14h", "25 de novembro de 2027".
// Hoje, amanhã e ontem pelo nome; até 6 dias para trás ou para frente, o dia da
// semana; depois, dia e mês, com o ano só quando não é o atual. O dia é comparado
// com diaDaMensagem (fuso da conta), nunca com o fuso do navegador.
import { diaDaMensagem } from 'dashboard/components-next/conversa-canal/dataDaConversa';

const DIAS_DA_SEMANA_PERTO = 6;
const UM_DIA = 86400000;

const formatadores = new Map();
const formatador = (idioma, opcoes) => {
  const chave = JSON.stringify([idioma, opcoes]);
  if (!formatadores.has(chave)) {
    formatadores.set(chave, new Intl.DateTimeFormat(idioma, opcoes));
  }
  return formatadores.get(chave);
};

const segundos = data => Math.floor(data.getTime() / 1000);

const diasEntre = (dataA, dataB, fuso) =>
  Math.round(
    (Date.parse(diaDaMensagem(segundos(dataA), fuso)) -
      Date.parse(diaDaMensagem(segundos(dataB), fuso))) /
      UM_DIA
  );

const parte = (partes, tipo) =>
  partes.find(item => item.type === tipo)?.value || '';

// "10h" ou "10h30".
export const horaFalada = (quando, fuso) => {
  const partes = formatador('en-GB', {
    timeZone: fuso,
    hour: 'numeric',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(quando);
  const hora = Number(parte(partes, 'hour'));
  const minuto = parte(partes, 'minute');
  return minuto === '00' ? `${hora}h` : `${hora}h${minuto}`;
};

// O índice do dia da semana no fuso da conta (0 = domingo).
const SEMANA_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const indiceDaSemana = (quando, fuso) =>
  SEMANA_EN.indexOf(
    formatador('en-US', { timeZone: fuso, weekday: 'short' }).format(quando)
  );

const anoNoFuso = (quando, fuso) =>
  formatador('en-US', { timeZone: fuso, year: 'numeric' }).format(quando);

// O dia sozinho: "hoje", "amanhã", "quinta", "25 de novembro".
export const diaFalado = ({ quando, agora, fuso, nomes, idioma = 'pt-BR' }) => {
  const diferenca = diasEntre(quando, agora, fuso);
  if (diferenca === 0) return nomes.hoje;
  if (diferenca === 1) return nomes.amanha;
  if (diferenca === -1) return nomes.ontem;
  if (Math.abs(diferenca) <= DIAS_DA_SEMANA_PERTO) {
    return nomes.semana[indiceDaSemana(quando, fuso)];
  }
  const mesmoAno = anoNoFuso(quando, fuso) === anoNoFuso(agora, fuso);
  return formatador(idioma, {
    timeZone: fuso,
    day: 'numeric',
    month: 'long',
    ...(mesmoAno ? {} : { year: 'numeric' }),
  }).format(quando);
};

export const primeiraMaiuscula = texto =>
  texto ? `${texto.charAt(0).toLocaleUpperCase()}${texto.slice(1)}` : '';
