// Loja mínima para montar a prévia da lista de conversas (#1702): a conta 1 com a
// chave da pele ligada ou não, e a caixa 5 do WhatsApp oficial.
import { createStore } from 'vuex';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const CAIXA_WHATSAPP = 5;

export const lojaDaLista = ({ ligada }) =>
  createStore({
    getters: {
      'accounts/getAccount': () => id => ({ id }),
      'accounts/isFeatureEnabledonAccount': () => (_, chave) =>
        ligada && chave === FEATURE_FLAGS.CONVERSA_CARA_DO_CANAL,
      'inboxes/getInbox': () => id =>
        Number(id) === CAIXA_WHATSAPP
          ? { id, channel_type: INBOX_TYPES.WHATSAPP }
          : {},
    },
  });
