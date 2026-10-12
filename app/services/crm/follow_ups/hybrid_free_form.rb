# Texto livre pelo WhatsApp API do Híbrido nos runners de IA (chat#1349): AutoFollowupRunner e CallbackRunner.
#
# Fora das 24h, numa caixa Oficial com o WhatsApp Híbrido pronto, o template continua vindo primeiro. Sem candidato
# nenhum, a composição já nasce em texto livre (uma chamada). Com candidatos, se a composição por template não deu
# mensagem enviável e não foi encerramento, faz uma 2ª chamada em texto livre, que decide sozinha se envia.
# O texto sai como mensagem de sessão; o roteador do Híbrido escolhe o transporte (origem crm_follow_up).
#
# Quem inclui precisa de `messaging_window`, `closure?`, `composable?` e `compose`, e ter @send_mode e @candidates
# definidos antes de chamar `detect_hybrid_free_form`.
module Crm::FollowUps::HybridFreeForm
  HYBRID_FREE_FORM = :hybrid_free_form
  TEMPLATE_METADATA_KEYS = %w[
    whatsapp_api_message_template_id template_name template_language template_processed_params template_category
  ].freeze

  private

  # Chamado depois de definir o modo e os candidatos: marca se o Híbrido está pronto e, sem candidato nenhum,
  # já passa para o texto livre.
  def detect_hybrid_free_form
    @hybrid_ready = @send_mode == :choose_template && messaging_window.hybrid_web_available?
    switch_to_hybrid_free_form('no_candidates') if @hybrid_ready && @candidates.empty?
  end

  def switch_to_hybrid_free_form(reason)
    @send_mode = HYBRID_FREE_FORM
    @hybrid_reason = reason
  end

  def hybrid_free_form?
    @send_mode == HYBRID_FREE_FORM
  end

  # Modo que o compositor entende: o texto livre pelo WhatsApp API compõe como free_form.
  def composer_mode
    hybrid_free_form? ? :free_form : @send_mode
  end

  # Segunda chamada: havia candidatos e a composição por template não deu mensagem enviável. Encerramento
  # (closure) nunca vira texto livre: para a cadência, ou vira lembrete, como sempre.
  def hybrid_free_form_retry?(composition)
    @send_mode == :choose_template && @hybrid_ready && !closure?(composition) && !composable?(composition)
  end

  # Compõe no modo escolhido; se couber a 2ª chamada em texto livre, devolve a composição dela.
  def compose_with_hybrid_retry
    composition = compose
    return composition unless hybrid_free_form_retry?(composition)

    switch_to_hybrid_free_form('template_declined')
    compose
  end

  # O MessageSender manda como mensagem de sessão (sem chave de template). O motivo fica gravado para responder
  # depois "por que este toque saiu pelo WhatsApp API".
  def apply_hybrid_free_form_metadata(metadata, composition)
    metadata['message_body'] = composition['message_body'].to_s.strip
    TEMPLATE_METADATA_KEYS.each { |key| metadata.delete(key) }
    metadata[Crm::FollowUps::MessageSender::TRANSPORT_KEY] = Crm::FollowUps::MessageSender::WHATSAPP_API_TRANSPORT
    metadata['hybrid_free_form_reason'] = @hybrid_reason
  end

  # Resto de uma tentativa anterior: o transporte vale só para a composição que o pediu.
  def clear_hybrid_free_form_metadata(metadata)
    metadata.delete(Crm::FollowUps::MessageSender::TRANSPORT_KEY)
    metadata.delete('hybrid_free_form_reason')
  end
end
