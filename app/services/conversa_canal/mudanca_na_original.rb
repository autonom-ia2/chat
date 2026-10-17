# Cliente apagou ou editou uma mensagem no WhatsApp (#1702). Os dois avisos só existem na coexistência e apontam a
# mensagem original pelo id dela; nenhum vira balão novo. Contrato acertado com o WhatsApp Híbrido (caixa WAHA grava o
# mesmo formato):
#
#   apagada:  content_attributes['deleted_by_contact_at'] = '2026-10-16T12:00:00Z'  (content e anexos intactos)
#   editada:  content = texto novo; content_attributes['edited_at'] = iso8601;
#             content_attributes['edit_history'] = [{ 'content' => anterior, 'edited_at', 'sender_type', 'sender_id' }]
#             (do mais antigo ao mais novo)
#
# Não usa `deleted = true` do Chatwoot: com ele a tela esconde o conteúdo, e o que o cliente mandou fica como prova.
# Original que não está aqui, que não veio do cliente, ou aviso vindo do próprio número (eco): nada muda (log info).
class ConversaCanal::MudancaNaOriginal
  APAGADA = 'revoke'.freeze
  EDITADA = 'edit'.freeze
  # Mesmo teto do WhatsApp Híbrido (#1709): as 10 versões anteriores mais recentes.
  LIMITE_DO_HISTORICO = 10

  def initialize(inbox:, data:, outgoing_echo: false)
    @inbox = inbox
    @data = data
    @outgoing_echo = outgoing_echo
  end

  # -> a mensagem original (mudada ou não), ou nil quando não há o que mudar.
  def perform
    return ignorar('echo') if @outgoing_echo

    original = mensagem_original
    return ignorar('original_not_found') if original.nil?
    return ignorar('not_from_contact') unless original.incoming?

    original.with_lock { tipo == APAGADA ? apagar(original) : editar(original) }
    original
  end

  private

  def tipo
    @data[:type]
  end

  def id_original
    (tipo == APAGADA ? @data.dig(:revoke, :original_message_id) : @data.dig(:edit, :original_message_id)).to_s
  end

  def mensagem_original
    return if id_original.blank?

    Message.where(inbox_id: @inbox.id).chat.find_by(source_id: id_original)
  end

  def apagar(original)
    attrs = original.content_attributes.to_h
    return if attrs['deleted_by_contact_at'].present?

    ConversaCanal::GravarNaMensagem.atualizar!(original, content_attributes: attrs.merge('deleted_by_contact_at' => quando.iso8601))
  end

  def editar(original)
    novo = texto_editado
    return ignorar('edit_without_text') if novo.blank?
    return if novo == original.content

    attrs = original.content_attributes.to_h
    historico = (Array(attrs['edit_history']) + [entrada_do_historico(original)]).last(LIMITE_DO_HISTORICO)
    ConversaCanal::GravarNaMensagem.atualizar!(
      original, content: novo, content_attributes: attrs.merge('edited_at' => quando.iso8601, 'edit_history' => historico)
    )
  end

  def entrada_do_historico(original)
    { 'content' => original.content, 'edited_at' => quando.iso8601,
      'sender_type' => original.sender_type, 'sender_id' => original.sender_id }
  end

  # A edição traz a mensagem nova inteira; o texto fica em `text.body` ou na legenda da mídia.
  def texto_editado
    nova = @data.dig(:edit, :message)
    return unless nova.respond_to?(:dig)

    nova.dig(:text, :body).presence || nova.dig(nova[:type], :caption).presence
  end

  def quando
    segundos = @data[:timestamp].to_i
    segundos.positive? ? Time.zone.at(segundos) : Time.current
  end

  def ignorar(motivo)
    Rails.logger.info("[conversa_canal][#{tipo}] ignored inbox=#{@inbox.id} reason=#{motivo}")
    nil
  end
end
