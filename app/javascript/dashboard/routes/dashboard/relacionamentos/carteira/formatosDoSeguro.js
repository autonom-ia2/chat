// #2897 — formatos da carteira: valor do seguro com centavos, data inteira e
// hora, sempre pelo Intl no idioma do painel (nunca texto montado à mão).
const MS_POR_SEGUNDO = 1000;

const formatadores = new Map();
const comFormatador = (Classe, idioma, opcoes) => {
  const chave = JSON.stringify([Classe.name, idioma, opcoes]);
  if (!formatadores.has(chave)) {
    formatadores.set(chave, new Classe(idioma, opcoes));
  }
  return formatadores.get(chave);
};

const emData = segundos => new Date(segundos * MS_POR_SEGUNDO);

// "R$ 2.760,00".
export const formatarValor = (valor, idioma) =>
  comFormatador(Intl.NumberFormat, idioma, {
    style: 'currency',
    currency: 'BRL',
  }).format(valor ?? 0);

// "29/11/2026".
export const formatarDataInteira = (segundos, idioma) =>
  comFormatador(Intl.DateTimeFormat, idioma, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(emData(segundos));

// "14:20".
export const formatarHora = (segundos, idioma) =>
  comFormatador(Intl.DateTimeFormat, idioma, {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(emData(segundos));

// O dia no formato do campo de data (`<input type="date">`): "2026-11-29".
export const paraCampoDeData = segundos => {
  const data = emData(segundos);
  const doisDigitos = numero => String(numero).padStart(2, '0');
  return [
    data.getFullYear(),
    doisDigitos(data.getMonth() + 1),
    doisDigitos(data.getDate()),
  ].join('-');
};

// Do campo de data para segundos, ao meio-dia (longe da virada do dia). Devolve
// null quando o campo está vazio ou a data não existe.
const MEIO_DIA = 12;
export const doCampoDeData = texto => {
  const [ano, mes, dia] = String(texto ?? '')
    .split('-')
    .map(Number);
  if (!ano || !mes || !dia) return null;
  const data = new Date(ano, mes - 1, dia, MEIO_DIA);
  return data.getMonth() === mes - 1
    ? Math.floor(data.getTime() / MS_POR_SEGUNDO)
    : null;
};

// O valor que a pessoa digitou ("2.760,50", "2760.5", "R$ 640") em número.
// Com vírgula, ela é o decimal e os pontos separam milhar. Sem vírgula, o ponto
// só é decimal quando sobra um ou dois dígitos depois dele. Devolve null quando
// não é um valor.
const ehDigito = char => char >= '0' && char <= '9';
export const valorDigitado = texto => {
  const limpo = [...String(texto ?? '')]
    .filter(char => ehDigito(char) || char === ',' || char === '.')
    .join('');
  if (!limpo || ![...limpo].some(ehDigito)) return null;
  const semMilhar = parte => parte.split('.').join('');
  if (limpo.includes(',')) {
    const [inteiro, ...decimais] = limpo.split(',');
    if (decimais.length !== 1) return null;
    return Number(`${semMilhar(inteiro) || '0'}.${decimais[0] || '0'}`);
  }
  const partes = limpo.split('.');
  const ultima = partes[partes.length - 1];
  const pontoDecimal = partes.length === 2 && ultima.length <= 2;
  return Number(pontoDecimal ? limpo : semMilhar(limpo));
};

// O número no jeito de digitar em reais: 2760.5 -> "2760,50".
export const valorParaCampo = valor =>
  valor === null || valor === undefined
    ? ''
    : Number(valor).toFixed(2).replace('.', ',');
