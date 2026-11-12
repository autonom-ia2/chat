// #2858 F7 — o preço dos cards Premium em texto de gente: "R$ 0,09" ou "de R$ 0,06 a R$ 0,15". Os valores vêm do
// servidor (`premium.precos`, em texto com ponto: "0.15"), na ordem do menor para o maior; aqui só se formata. Todo
// preço fecha em centavos inteiros (o servidor garante). Sem regex: `Number` e `Intl.NumberFormat` (sempre em reais,
// no idioma da tela).

const formatador = locale =>
  new Intl.NumberFormat(locale === 'en' ? 'en-US' : 'pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

export const emReais = (valor, locale = 'pt_BR') =>
  formatador(locale).format(Number(valor));

// -> { unico: 'R$ 0,09' } ou { min: 'R$ 0,06', max: 'R$ 0,15' }; null sem preço.
export const faixaDePreco = (precos, locale = 'pt_BR') => {
  const valores = (precos || [])
    .map(Number)
    .filter(Number.isFinite)
    .sort((a, b) => a - b);
  if (!valores.length) return null;
  const min = emReais(valores[0], locale);
  const max = emReais(valores[valores.length - 1], locale);
  return min === max ? { unico: min } : { min, max };
};

// Em que ponto estão as grátis do mês: 'RESTAM' (duas ou mais), 'RESTA_UMA' ou 'ACABARAM'. A tela muda o texto e a cor
// por aqui; o número vem do servidor.
export const estadoDasGratis = restantes => {
  const n = Number(restantes) || 0;
  if (n <= 0) return 'ACABARAM';
  return n === 1 ? 'RESTA_UMA' : 'RESTAM';
};

// Uma marca por consulta grátis do mês (20): true nas que ainda restam. É a barrinha do cartão e do "Quanto custa".
export const marcasDasGratis = (gratis, restantes) => {
  const total = Math.max(Number(gratis) || 0, 0);
  const sobram = Math.min(Math.max(Number(restantes) || 0, 0), total);
  return Array.from({ length: total }, (_, indice) => indice < sobram);
};
