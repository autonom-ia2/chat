// Diz se uma caixa é de e-mail e a conta tem a chave conversa_email_nova (#1809).
import { useMapGetter } from 'dashboard/composables/store';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const caixaDaFolha = folha => folha?.to?.params?.inbox_id;

export const useCaixaDeEmailNova = () => {
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const contaAtual = useMapGetter('getCurrentAccountId');
  const temChave = useMapGetter('accounts/isFeatureEnabledonAccount');
  return caixaId =>
    Boolean(caixaId) &&
    caixaPorId.value(Number(caixaId))?.channel_type === INBOX_TYPES.EMAIL &&
    temChave.value(contaAtual.value, 'conversa_email_nova');
};
