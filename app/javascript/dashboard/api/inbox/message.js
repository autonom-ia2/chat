/* eslint no-console: 0 */
/* global axios */
import ApiClient from '../ApiClient';

export const buildCreatePayload = ({
  message,
  isPrivate,
  contentAttributes,
  echoId,
  files,
  ccEmails = '',
  bccEmails = '',
  toEmails = '',
  templateParams,
  isVoiceMessage = false,
  documentIndexes = [],
  ficarComAConversa,
  ficarComAConversaDe,
}) => {
  let payload;
  if (files && files.length !== 0) {
    payload = new FormData();
    if (message) {
      payload.append('content', message);
    }
    files.forEach(file => {
      payload.append('attachments[]', file);
    });
    payload.append('private', isPrivate);
    payload.append('echo_id', echoId);
    payload.append('cc_emails', ccEmails);
    payload.append('bcc_emails', bccEmails);

    if (toEmails) {
      payload.append('to_emails', toEmails);
    }
    if (contentAttributes) {
      payload.append('content_attributes', JSON.stringify(contentAttributes));
    }
    if (isVoiceMessage) {
      payload.append('is_voice_message', true);
    }
    // #1702: "Documento" do "+" — esses anexos (pela posição em files) vão como
    // documento, mesmo sendo foto ou vídeo.
    documentIndexes.forEach(indice => {
      payload.append('document_indexes[]', indice);
    });
    // #2067: o ícone "ficar com a conversa" e o dono que a tela viu (só com a flag da conta).
    if (typeof ficarComAConversa === 'boolean') {
      payload.append('ficar_com_a_conversa', ficarComAConversa);
      if (ficarComAConversaDe?.tipo) {
        payload.append(
          'ficar_com_a_conversa_de[tipo]',
          ficarComAConversaDe.tipo
        );
      }
      if (ficarComAConversaDe?.id) {
        payload.append('ficar_com_a_conversa_de[id]', ficarComAConversaDe.id);
      }
    }
  } else {
    payload = {
      content: message,
      private: isPrivate,
      echo_id: echoId,
      content_attributes: contentAttributes,
      cc_emails: ccEmails,
      bcc_emails: bccEmails,
      to_emails: toEmails,
      template_params: templateParams,
      // #2067: o ícone "ficar com a conversa ao enviar" e o dono que a tela viu; sem eles
      // (flag desligada), o servidor segue a regra de antes.
      ficar_com_a_conversa: ficarComAConversa,
      ficar_com_a_conversa_de: ficarComAConversaDe,
    };
  }
  return payload;
};

class MessageApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create({
    conversationId,
    message,
    private: isPrivate,
    contentAttributes,
    echo_id: echoId,
    files,
    ccEmails = '',
    bccEmails = '',
    toEmails = '',
    templateParams,
    isVoiceMessage = false,
    documentIndexes = [],
    ficarComAConversa,
    ficarComAConversaDe,
  }) {
    return axios({
      method: 'post',
      url: `${this.url}/${conversationId}/messages`,
      data: buildCreatePayload({
        message,
        isPrivate,
        contentAttributes,
        echoId,
        files,
        ccEmails,
        bccEmails,
        toEmails,
        templateParams,
        isVoiceMessage,
        documentIndexes,
        ficarComAConversa,
        ficarComAConversaDe,
      }),
    });
  }

  delete(conversationID, messageId) {
    return axios.delete(`${this.url}/${conversationID}/messages/${messageId}`);
  }

  retry(conversationID, messageId) {
    return axios.post(
      `${this.url}/${conversationID}/messages/${messageId}/retry`
    );
  }

  getPreviousMessages({ conversationId, after, before }) {
    const params = { before };
    if (after && Number(after) !== Number(before)) {
      params.after = after;
    }
    return axios.get(`${this.url}/${conversationId}/messages`, { params });
  }

  translateMessage(conversationId, messageId, targetLanguage) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/translate`,
      {
        target_language: targetLanguage,
      }
    );
  }
}

export default new MessageApi();
