# Cópia do e-mail enviado pelo painel na pasta de enviados da conta do cliente (#1938, parte B). Quem abre o Webmail ou
# o Outlook vê o que a equipe respondeu. Só caixa com IMAP ligado que envia por SMTP; a Microsoft envia pelo Graph, que
# já guarda nos Itens Enviados.
# - A pasta é a que o servidor marca como de enviados (atributo \Sent, RFC 6154). Sem essa marca, nada é gravado: o
#   nome da pasta muda por provedor e idioma, e chutar grava no lugar errado.
# - Provedor que já guarda o que sai pelo SMTP dele (Gmail, Outlook): a mensagem já está lá, achada pelo Message-ID, e
#   nada é gravado. Só falta a cópia: APPEND, já lida.
# - A cópia é o mesmo e-mail montado de novo pelo ConversationReplyMailer, com o Message-ID e a data do envio.
class ConversaCanal::CopiaNoEnviados
  # O que o servidor responde: :gravada, :ja_estava ou :sem_pasta.
  def initialize(message)
    @message = message
    @channel = message.inbox.channel
  end

  def self.aplica?(message)
    channel = message.inbox&.channel
    channel.is_a?(Channel::Email) && channel.imap_enabled? && !channel.microsoft? &&
      message.account.feature_enabled?('email_enviados') && message.source_id.present? && !message.failed?
  end

  def gravar
    email = montar
    return :sem_email if email.nil?

    ConversaCanal::ConexaoDoEmail.abrir(@channel) do |imap, lock|
      pasta = pasta_de_enviados(imap)
      next :sem_pasta if pasta.nil?

      lock.renovar!
      next :ja_estava if ja_esta?(imap, pasta)

      lock.renovar!
      imap.append(pasta, email.to_s, [:Seen], @message.created_at)
      :gravada
    end
  end

  private

  def montar
    email = ConversationReplyMailer.with(account: @message.account).email_reply(@message).message
    return nil if email.to.blank?

    email.message_id = @message.source_id
    email.date = @message.created_at
    email
  end

  def pasta_de_enviados(imap)
    imap.list('', '*')&.find { |pasta| pasta.attr.include?(:Sent) }&.name
  end

  def ja_esta?(imap, pasta)
    imap.examine(pasta)
    imap.uid_search(['HEADER', 'Message-ID', @message.source_id]).any?
  end
end
