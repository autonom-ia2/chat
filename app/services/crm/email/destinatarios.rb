# PARA QUEM VAI A RESPOSTA POR E-MAIL (#1828): a mesma regra do "Responder a todos" que o painel usa para preencher
# Para/Cc/Cco (`getRecipients` do @chatwoot/utils, chamado no ReplyBox#setCCAndToEmailsFromLastChat), portada para o
# back para a resposta da IA (Autonomia::Agents::Operate::Responder) usar a mesma coisa:
#
#   Crm::Email::Destinatarios.new(conversation).perform # => { to: [...], cc: [...], bcc: [...] }
#
# A partir da última mensagem pública da conversa (recebida ou enviada):
# - recebida: Para = quem mandou; Cc = o Cc dela, mais o cliente se não foi ele quem mandou; Cco = o Cco dela sem o
#   cliente;
# - enviada: Para = o Para dela (ou o cliente); Cc e Cco = os dela;
# - do Cc saem o cliente (quando ele mesmo mandou a última); do Cc e do Cco, o endereço da caixa, o de encaminhamento
#   dela e os endereços de resposta da plataforma ("reply+<uuid>@", o mesmo padrão do ApplicationMailbox); do Cco, o
#   cliente.
# A resposta da IA (#para_a_ia) usa as mesmas pessoas, com o cliente sempre no Para.
# Ninguém novo entra: só endereços da última mensagem e o do cliente.
#
# Melhor que o Gmail (#1828): quem pediu para sair da cópia NESTA conversa (Crm::FollowUps::OptOutDecision grava em
# `additional_attributes[CHAVE]`) sai do Para, do Cc e do Cco. O cliente nunca sai; Para vazio volta a ser o cliente.
class Crm::Email::Destinatarios
  CHAVE = 'email_saiu_da_copia'.freeze

  # #1828 (flag `email_autoria`): os destinatários da resposta da IA como parâmetros do MessageBuilder (`to_emails`,
  # `cc_emails`, `bcc_emails`), como o "Responder a todos" do painel, sem quem pediu para sair. Fora do e-mail, ou sem a
  # flag, {}: a resposta vai só ao cliente. Usado pela resposta do turno (Responder#post_reply!) e pela interação que sai
  # depois do áudio (Operate::InteracaoDepoisDoAudio), calculado na hora de postar.
  def self.da_ia(conversation)
    return {} unless conversation.inbox&.email? && Crm::Email::Autoria.ligada?(conversation.account)

    new(conversation).para_a_ia.to_h { |campo, enderecos| [:"#{campo}_emails", enderecos.join(',')] }
  end

  def self.saiu_da_copia(conversation)
    Array(conversation&.additional_attributes.to_h[CHAVE]).map { |endereco| endereco.to_s.strip.downcase }
  end

  # Quem pediu para sair desta conversa. O cliente nunca entra na lista.
  # Trava a conversa e relê antes de juntar: outra escrita em additional_attributes no meio não se perde.
  def self.registrar_saida!(conversation, endereco)
    endereco = endereco.to_s.strip.downcase
    return if endereco.empty? || endereco == conversation.contact&.email.to_s.strip.downcase

    Conversation.transaction do
      travada = Conversation.lock.find(conversation.id)
      next if saiu_da_copia(travada).include?(endereco)

      travada.update!(additional_attributes: travada.additional_attributes.to_h.merge(CHAVE => saiu_da_copia(travada) + [endereco]))
    end
  end

  def initialize(conversation)
    @conversation = conversation
    @contato = conversation.contact&.email.to_s.strip.downcase
  end

  # O preenchimento do painel ("Responder a todos"), sem quem saiu.
  def perform
    ultima = ultima_mensagem
    return { to: [], cc: [], bcc: [] } if ultima.nil?

    destinos = ultima.incoming? ? da_recebida(ultima) : da_enviada(ultima)
    sem_quem_saiu(destinos.merge(bcc: limpar_bcc(destinos[:bcc])))
  end

  # A resposta da IA: as mesmas pessoas, mas o Para é sempre o cliente (#1828: "o cliente já é o destinatário"); quem
  # o painel poria no Para (ex.: a Ana, que escreveu por último) vai em cópia. A IA nunca responde só a outra pessoa.
  def para_a_ia
    destinos = perform
    return destinos if @contato.empty?

    { to: [@contato], cc: (destinos[:to] + destinos[:cc]).uniq - [@contato], bcc: destinos[:bcc] - [@contato] }
  end

  private

  def ultima_mensagem
    @conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(id: :desc).first
  end

  def da_recebida(message)
    email = message.content_attributes['email']
    email = email.is_a?(Hash) ? email.with_indifferent_access : {}
    de = lista(email[:from])
    do_cliente = de.include?(@contato)
    cc = lista(email[:cc])
    cc << @contato unless do_cliente
    { to: de, cc: limpar_cc(cc, do_cliente), bcc: lista(email[:bcc]) }
  end

  def da_enviada(message)
    atributos = message.content_attributes.to_h.with_indifferent_access
    para = lista(atributos[:to_emails])
    { to: para.presence || [@contato], cc: limpar_cc(lista(atributos[:cc_emails]), false), bcc: lista(atributos[:bcc_emails]) }
  end

  def limpar_cc(cc, do_cliente)
    cc.reject { |endereco| (do_cliente && endereco == @contato) || da_plataforma?(endereco) }
  end

  # Cco, nos dois casos (recebida e enviada), como no painel: sem o cliente (já está em Para ou Cc) e sem a plataforma.
  def limpar_bcc(bcc)
    bcc.reject { |endereco| endereco == @contato || da_plataforma?(endereco) }
  end

  # A caixa, o encaminhamento dela e o endereço de resposta da conversa ("reply+<uuid>@"), para não voltar à caixa.
  def da_plataforma?(endereco)
    da_caixa.include?(endereco) || endereco.split('@').first.to_s.match?(ApplicationMailbox::REPLY_EMAIL_UUID_PATTERN)
  end

  def sem_quem_saiu(destinos)
    saiu = self.class.saiu_da_copia(@conversation) - [@contato]
    limpos = destinos.transform_values { |enderecos| (enderecos - saiu).compact_blank.uniq }
    limpos[:to] = [@contato].compact_blank if limpos[:to].empty?
    limpos
  end

  def da_caixa
    @da_caixa ||= begin
      canal = @conversation.inbox&.channel
      canal.is_a?(Channel::Email) ? [canal.email, canal.forward_to_email].map { |endereco| endereco.to_s.downcase } : []
    end
  end

  # Só endereço que o Messages::MessageBuilder aceita (EmailHelper#validate_email_addresses, a mesma checagem): um
  # inválido no Cc de um e-mail recebido faria a resposta inteira falhar.
  def lista(valor)
    Array(valor).map { |endereco| endereco.to_s.strip.downcase }.grep(URI::MailTo::EMAIL_REGEXP)
  end
end
