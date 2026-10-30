// #2138 — incluir ou tirar só a própria pessoa de quem acompanha a conversa. A
// chamada leva só o id dela (POST para entrar, DELETE para sair): a lista das
// outras pessoas nunca é enviada, então não há como apagar quem uma colega incluiu.
import AcompanharConversaAPI from 'dashboard/api/acompanharConversa';

export const lerQuemAcompanha = async conversationId => {
  const { data } = await AcompanharConversaAPI.quemAcompanha(conversationId);
  if (!Array.isArray(data)) throw new Error('lista de quem acompanha ilegível');
  return data.map(pessoa => pessoa.id);
};

// Grava e confere na lista lida depois. Devolve true quando a pessoa ficou como
// pedido. Se a releitura falhar, vale a resposta da gravação (que deu certo).
export const mudarAcompanhar = async ({ conversationId, euId, acompanhar }) => {
  if (acompanhar) await AcompanharConversaAPI.incluir(conversationId, euId);
  else await AcompanharConversaAPI.tirar(conversationId, euId);
  try {
    const ids = await lerQuemAcompanha(conversationId);
    return ids.includes(euId) === acompanhar;
  } catch {
    return true;
  }
};
