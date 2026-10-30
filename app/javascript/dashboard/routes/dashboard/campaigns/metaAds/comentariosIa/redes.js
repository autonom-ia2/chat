// Comentários que viram cliente (#2212): a mesma chave de texto em três versões, pela rede de onde vêm os comentários.
// No Instagram a mensagem vai no privado (Direct); no Facebook, no Messenger; no anúncio, nas duas.
const SUFFIX = { instagram: '', facebook: '_FACEBOOK', both: '_BOTH' };

export const porRede = (key, network) => `${key}${SUFFIX[network] ?? ''}`;
