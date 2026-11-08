// Comentários que viram cliente (#2212): a mesma chave de texto em três versões, pela rede de onde vêm os comentários.
// No Instagram a mensagem vai no privado (Direct); no Facebook, no Messenger; no anúncio, nas duas.
const SUFFIX = { instagram: '', facebook: '_FACEBOOK', both: '_BOTH' };

export const porRede = (key, network) => `${key}${SUFFIX[network] ?? ''}`;

// "1 recebeu no privado · 0 responderam": a forma de cada número escolhida aqui (1 = singular), sem depender da escolha
// de plural do vue-i18n, que pegava o singular para o 0. A tela ligada e a faixa de Seus posts usam a mesma linha.
const KEY = 'META_ADS_COMMENTS_AI.ON';
const one = (key, count) => (count === 1 ? `${key}_ONE` : key);
export const linhaDoResultado = (t, network, results, format) => {
  const sent = Number(results?.sent) || 0;
  const replied = Number(results?.replied) || 0;
  const valores = { sent: format(sent), replied: format(replied) };
  return `${t(one(porRede(`${KEY}.RESULT`, network), sent), valores)} · ${t(one(`${KEY}.REPLIED`, replied), valores)}`;
};
