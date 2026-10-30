// Anúncios da Meta (#2198): o valor em reais escrito por extenso, para a confirmação que mexe no dinheiro do cliente
// ("R$ 45,00 (quarenta e cinco reais) por dia"). Só real: outra moeda volta null e a tela mostra só o número.
// Em português e em inglês (a gravação para a Meta é em inglês). Até 999 milhões, o bastante para orçamento.

const PT = {
  units: [
    'zero',
    'um',
    'dois',
    'três',
    'quatro',
    'cinco',
    'seis',
    'sete',
    'oito',
    'nove',
    'dez',
    'onze',
    'doze',
    'treze',
    'catorze',
    'quinze',
    'dezesseis',
    'dezessete',
    'dezoito',
    'dezenove',
  ],
  tens: [
    '',
    '',
    'vinte',
    'trinta',
    'quarenta',
    'cinquenta',
    'sessenta',
    'setenta',
    'oitenta',
    'noventa',
  ],
  hundreds: [
    '',
    'cento',
    'duzentos',
    'trezentos',
    'quatrocentos',
    'quinhentos',
    'seiscentos',
    'setecentos',
    'oitocentos',
    'novecentos',
  ],
};

const EN = {
  units: [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ],
  tens: [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ],
};

// 1 a 999 em português: "cem" sozinho, "cento e um"; partes ligadas por "e".
const ptHundreds = value => {
  if (value === 100) return 'cem';
  const parts = [];
  const hundred = Math.floor(value / 100);
  const rest = value % 100;
  if (hundred) parts.push(PT.hundreds[hundred]);
  if (rest >= 20) {
    parts.push(PT.tens[Math.floor(rest / 10)]);
    if (rest % 10) parts.push(PT.units[rest % 10]);
  } else if (rest) {
    parts.push(PT.units[rest]);
  }
  return parts.join(' e ');
};

// Entre grupos, "e" só quando o grupo de baixo é menor que cem ou redondo: "mil e cinquenta", "mil e trezentos",
// "mil trezentos e cinquenta".
const ptJoin = (high, low) => {
  if (!low) return high;
  const glue = low.value < 100 || low.value % 100 === 0 ? ' e ' : ' ';
  return `${high}${glue}${low.text}`;
};

const ptInteger = value => {
  if (value === 0) return PT.units[0];
  const millions = Math.floor(value / 1_000_000);
  const thousands = Math.floor((value % 1_000_000) / 1000);
  const rest = value % 1000;
  let text = null;
  let lowValue = 0;
  if (rest) {
    text = ptHundreds(rest);
    lowValue = rest;
  }
  if (thousands) {
    const high = thousands === 1 ? 'mil' : `${ptHundreds(thousands)} mil`;
    text = text ? ptJoin(high, { value: lowValue, text }) : high;
    lowValue += thousands * 1000;
  }
  if (millions) {
    const high = `${ptHundreds(millions)} ${millions === 1 ? 'milhão' : 'milhões'}`;
    text = text ? ptJoin(high, { value: lowValue, text }) : high;
  }
  return text;
};

const enHundreds = value => {
  const parts = [];
  const hundred = Math.floor(value / 100);
  const rest = value % 100;
  if (hundred) parts.push(`${EN.units[hundred]} hundred`);
  if (rest >= 20) {
    const ten = EN.tens[Math.floor(rest / 10)];
    parts.push(rest % 10 ? `${ten}-${EN.units[rest % 10]}` : ten);
  } else if (rest) {
    parts.push(EN.units[rest]);
  }
  return parts.join(' ');
};

const enInteger = value => {
  if (value === 0) return EN.units[0];
  const groups = [
    [Math.floor(value / 1_000_000), 'million'],
    [Math.floor((value % 1_000_000) / 1000), 'thousand'],
    [value % 1000, ''],
  ];
  return groups
    .filter(([group]) => group)
    .map(([group, name]) => [enHundreds(group), name].filter(Boolean).join(' '))
    .join(' ');
};

const ptMoney = (reais, centavos) => {
  const parts = [];
  if (reais) {
    // "um milhão de reais", "dois milhões de reais": milhão redondo leva "de".
    const round = reais >= 1_000_000 && reais % 1_000_000 === 0;
    const unit = reais === 1 ? 'real' : 'reais';
    parts.push(`${ptInteger(reais)}${round ? ' de' : ''} ${unit}`);
  }
  if (centavos) {
    parts.push(
      `${ptInteger(centavos)} ${centavos === 1 ? 'centavo' : 'centavos'}`
    );
  }
  return parts.length ? parts.join(' e ') : 'zero real';
};

const enMoney = (reais, centavos) => {
  const parts = [];
  if (reais)
    parts.push(`${enInteger(reais)} ${reais === 1 ? 'real' : 'reais'}`);
  if (centavos) {
    parts.push(
      `${enInteger(centavos)} ${centavos === 1 ? 'centavo' : 'centavos'}`
    );
  }
  return parts.length ? parts.join(' and ') : 'zero reais';
};

const LIMIT = 1_000_000_000;

// valor: número em reais (45.5). locale: o do painel ('pt_BR', 'en'…).
export const valorPorExtenso = (valor, currency, locale) => {
  const number = Number(valor);
  if (currency !== 'BRL' || !Number.isFinite(number) || number < 0) return null;
  const cents = Math.round(number * 100);
  if (cents >= LIMIT * 100) return null;
  const reais = Math.floor(cents / 100);
  const centavos = cents % 100;
  return String(locale || '').startsWith('pt')
    ? ptMoney(reais, centavos)
    : enMoney(reais, centavos);
};
