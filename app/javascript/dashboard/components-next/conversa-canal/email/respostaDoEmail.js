// Quem vai em Para, Cc e Cco em cada ação da conversa de e-mail (#1786):
// Responder = só quem escreveu; Responder a todos = quem escreveu em Para e os demais
// em Cc (a mesma regra do Chatwoot, getRecipients); Encaminhar = destinatário em branco.
// O histórico e o original encaminhado não entram no texto do atendente: vão embaixo,
// formatados, montados pelo servidor (ConversaCanal::CitacaoDoEmail).
import { getRecipients } from '@chatwoot/utils';
import { MODOS_DE_RESPOSTA } from './useConversaDeEmail';

const juntar = lista => (lista || []).join(', ');

export const montarRespostaDoEmail = ({ modo, mensagem, contato, caixa }) => {
  if (modo === MODOS_DE_RESPOSTA.ENCAMINHAR) {
    return { para: '', cc: '', cco: '' };
  }
  const { to, cc, bcc } = getRecipients(
    mensagem,
    contato || '',
    caixa?.email || '',
    caixa?.forward_to_email || ''
  );
  if (modo === MODOS_DE_RESPOSTA.TODOS) {
    return { para: juntar(to), cc: juntar(cc), cco: juntar(bcc) };
  }
  return { para: juntar(to), cc: '', cco: '' };
};
