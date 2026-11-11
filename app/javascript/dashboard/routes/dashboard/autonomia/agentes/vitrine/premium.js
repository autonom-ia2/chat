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
