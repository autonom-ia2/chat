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
  subject,
  templateParams,
  isVoiceMessage = false,
  documentIndexes = [],
  ficarComAConversa,
  ficarComAConversaDe,
  reabrirAoEscrever = false,
  emailHtmlContent,
  forwardedAttachmentIds,
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
    if (subject) {
      payload.append('subject', subject);
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
    // #2216: a gaveta Nova conversa na conversa visível de caixa com "Reabrir a mesma
    // conversa": o servidor reabre a resolvida ou adiada, sem mudar quem cuida.
    if (reabrirAoEscrever) {
      payload.append('reabrir_ao_escrever', true);
    }
    if (emailHtmlContent) {
      payload.append('email_html_content', emailHtmlContent);
    }
    forwardedAttachmentIds?.forEach(id => {
      payload.append('forwarded_attachment_ids[]', id);
    });
  } else {
    payload = {
      content: message,
      private: isPrivate,
      echo_id: echoId,
      content_attributes: contentAttributes,
      cc_emails: ccEmails,
      bcc_emails: bccEmails,
      to_emails: toEmails,
      subject,
      template_params: templateParams,
      // #2067: o ícone "ficar com a conversa ao enviar" e o dono que a tela viu; sem eles
      // (flag desligada), o servidor segue a regra de antes.
      ficar_com_a_conversa: ficarComAConversa,
      ficar_com_a_conversa_de: ficarComAConversaDe,
      // #2216: só a gaveta Nova conversa manda (ver acima).
      ...(reabrirAoEscrever ? { reabrir_ao_escrever: true } : {}),
      email_html_content: emailHtmlContent,
      forwarded_attachment_ids: forwardedAttachmentIds,
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
    subject,
    templateParams,
    isVoiceMessage = false,
    documentIndexes = [],
    ficarComAConversa,
    ficarComAConversaDe,
    reabrirAoEscrever = false,
    emailHtmlContent,
    forwardedAttachmentIds,
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
        subject,
        templateParams,
        isVoiceMessage,
        documentIndexes,
        ficarComAConversa,
        ficarComAConversaDe,
        reabrirAoEscrever,
        emailHtmlContent,
        forwardedAttachmentIds,
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

  autoTranslate(conversationId, messageIds) {
    return axios.post(`${this.url}/${conversationId}/messages/auto_translate`, {
      message_ids: messageIds,
    });
  }
}

export default new MessageApi();
