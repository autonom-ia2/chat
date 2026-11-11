// #2894 — formatos da ficha: documento com pontuação, datas no idioma do painel
// (Intl, nunca texto montado à mão), "há 3 dias" e valor em reais.
import { soDigitos } from '../fonte/texto';

const TAMANHO_CPF = 11;
const TAMANHO_CNPJ = 14;
const MS_POR_SEGUNDO = 1000;
const SEGUNDOS_POR_MINUTO = 60;
const MINUTOS_POR_HORA = 60;
const HORAS_POR_DIA = 24;
const DIAS_POR_MES = 30;
const MESES_POR_ANO = 12;

const formatadores = new Map();
const comFormatador = (Classe, idioma, opcoes) => {
  const chave = JSON.stringify([Classe.name, idioma, opcoes]);
  if (!formatadores.has(chave)) {
    formatadores.set(chave, new Classe(idioma, opcoes));
  }
  return formatadores.get(chave);
};

const emData = segundos => new Date(segundos * MS_POR_SEGUNDO);

export const formatarCpf = valor => {
  const d = soDigitos(valor);
  if (d.length !== TAMANHO_CPF) return String(valor ?? '');
  return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
};

export const formatarCnpj = valor => {
  const d = soDigitos(valor);
  if (d.length !== TAMANHO_CNPJ) return String(valor ?? '');
  const raiz = `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}`;
  return `${raiz}/${d.slice(8, 12)}-${d.slice(12)}`;
};

// "mar. de 2024" (pt-BR) / "Mar 2024" (en).
export const formatarMes = (segundos, idioma) =>
  comFormatador(Intl.DateTimeFormat, idioma, {
    month: 'short',
    year: 'numeric',
  }).format(emData(segundos));

// "12/09" (pt-BR) / "09/12" (en). Com `agoraEmMs`, data de outro ano leva o
// ano: "27/11/2025".
export const formatarDiaMes = (segundos, idioma, agoraEmMs = null) => {
  const doAnoCorrente =
    agoraEmMs === null ||
    emData(segundos).getFullYear() === new Date(agoraEmMs).getFullYear();
  return comFormatador(Intl.DateTimeFormat, idioma, {
    day: '2-digit',
    month: '2-digit',
    ...(doAnoCorrente ? {} : { year: 'numeric' }),
  }).format(emData(segundos));
};

export const formatarReais = (valor, idioma) =>
  comFormatador(Intl.NumberFormat, idioma, {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(valor ?? 0);

// "há 3 dias", "ontem", "agora": a unidade maior que couber.
export const quandoRelativo = (segundos, agoraEmMs, idioma) => {
  const formato = comFormatador(Intl.RelativeTimeFormat, idioma, {
    numeric: 'auto',
  });
  const passados = Math.max(
    0,
    Math.floor(agoraEmMs / MS_POR_SEGUNDO - segundos)
  );
  const minutos = Math.floor(passados / SEGUNDOS_POR_MINUTO);
  const horas = Math.floor(minutos / MINUTOS_POR_HORA);
  const dias = Math.floor(horas / HORAS_POR_DIA);
  const meses = Math.floor(dias / DIAS_POR_MES);
  if (minutos < 1) return formato.format(0, 'second');
  if (horas < 1) return formato.format(-minutos, 'minute');
  if (dias < 1) return formato.format(-horas, 'hour');
  if (meses < 1) return formato.format(-dias, 'day');
  if (meses < MESES_POR_ANO) return formato.format(-meses, 'month');
  return formato.format(-Math.floor(meses / MESES_POR_ANO), 'year');
};
