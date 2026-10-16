# Retorno combinado fora das 24h com o pré-voo (#1624) no CallbackRunner: reusa a composição que o pré-voo gravou e, quando nenhum
# modelo aprovado serve, envia pelo modelo do tipo `retorno` do ponto único (Whatsapp::Templates::EnvioForaDaJanela) ANTES do
# texto livre pelo Híbrido (ordem do épico #1585: modelo aprovado, criar, Híbrido, aviso).
# Quem inclui precisa de `compose`, `closure?`, `resolved_candidate`, `capped?`, `deliver`, `base_metadata`, `parse_time`,
# `service_reminder?`, `callback_template_candidates`, `hybrid_free_form_retry?` e `switch_to_hybrid_free_form`, e ter @send_mode e
# @candidates definidos antes de usar `composicao_gravada`.
module Crm::FollowUps::RetornoPorModelo
  # Contato excluído do follow-up de IA: o retorno combinado vira lembrete humano, a IA não envia. O pré-voo também pergunta,
  # para não criar modelo para quem não vai receber.
  def precondition_fallback_reason
    return 'card_archived' if @card&.archived?
    return 'no_conversation' if @follow_up.conversation.blank?

    contact = @follow_up.conversation.contact
    return Crm::FollowUps::MessageSender::OPTED_OUT_REASON if contact.opted_out?

    'contact_disabled' if Crm::Ai::Config.contact_followup_disabled?(contact)
  end

  # Pré-voo: a mesma composição por modelo aprovado que o envio faria, uma chamada paga. Devolve a composição e a assinatura da lista
  # de modelos em que ela escolheu (o índice só vale para a mesma lista).
  def compor_antes
    @send_mode = :choose_template
    @candidates = callback_template_candidates
    detect_hybrid_free_form
    # Sem modelo aprovado e com o Híbrido pronto, o envio vai direto ao texto livre: não há o que compor nem criar agora.
    [(compose unless hybrid_free_form?), assinatura_dos_candidatos]
  end

  # A IA disse que há o que enviar e nenhum modelo aprovado serve: é aqui que o modelo do tipo (retorno) entra.
  def precisa_do_modelo_do_tipo?(composition)
    return false unless @send_mode == :choose_template && !service_reminder? && composition.present? && !closure?(composition)

    composition['decline_reason'].to_s == 'no_fitting_template' || escolha_sem_modelo?(composition)
  end

  private

  # Fora das 24h o template vem primeiro; sem candidato nenhum e com o Híbrido pronto, vai ao texto livre.
  def definir_modo_e_candidatos
    @send_mode = messaging_window.can_send_session_message? ? :free_form : :choose_template
    @candidates = @send_mode == :choose_template ? callback_template_candidates : []
    detect_hybrid_free_form
  end

  # Quis enviar com confiança, mas o índice escolhido não existe na lista de modelos aprovados.
  def escolha_sem_modelo?(composition)
    Crm::Ai::Config::BOOLEAN.cast(composition['should_send']) &&
      composition['confidence'].to_f >= Crm::Ai::Config::FOLLOWUP_MIN_CONFIDENCE && resolved_candidate(composition).blank?
  end

  # A composição que o pré-voo gravou, só enquanto ela ainda descreve a situação: mesmo horário, do mesmo tipo de envio (modelo
  # aprovado, sem Híbrido), recente, a mesma lista de modelos e sem tentativa anterior falhada. Se o cliente respondeu, a janela de
  # 24 h reabriu e o envio já não é por modelo (@send_mode), então nada é reusado. Qualquer dúvida e o runner compõe de novo.
  def composicao_gravada
    marca = Crm::FollowUps::Preflight.marca_vigente(@follow_up)
    return unless marca && @send_mode == :choose_template && composicao_ainda_vale?(marca)

    @context ||= Crm::Ai::ContextBuilder.new(card: @card).perform
    marca['composicao']
  end

  def composicao_ainda_vale?(marca)
    feita_em = parse_time(marca['at'])
    marca['composicao'].is_a?(Hash) && feita_em.present? && base_metadata['callback_retries'].to_i.zero? &&
      @now - feita_em <= Crm::FollowUps::Preflight::VALIDADE && marca['candidatos'] == assinatura_dos_candidatos
  end

  def assinatura_dos_candidatos
    @candidates.map { |candidate| [candidate[:kind], candidate[:name], candidate[:id], candidate[:language]] }
  end

  # O modelo do tipo (retorno), pelo ponto único: o do pré-voo ou o que já estiver aprovado. nil: segue para o texto livre pelo
  # Híbrido ou o aviso (o motivo fica para o aviso, se nada mais servir).
  def entrega_pelo_modelo_do_tipo(composition)
    return unless precisa_do_modelo_do_tipo?(composition) && inbox_oficial?

    envio = Crm::FollowUps::EnvioForaDaJanela.new(follow_up: @follow_up, card: @card).call
    unless envio.enviar?
      @motivo_do_modelo = envio.motivo
      return
    end

    gravar_envio_do_modelo(envio)
    return self.class::Result.failed('marketing_cap', @now + self.class::MARKETING_CAP_WINDOW) if capped?

    deliver
  end

  def gravar_envio_do_modelo(envio)
    metadata = base_metadata
    clear_hybrid_free_form_metadata(metadata)
    metadata.delete('whatsapp_api_message_template_id')
    @follow_up.update!(metadata: metadata.merge(envio.metadata))
  end

  # Só o número oficial (Channel::Whatsapp) manda modelo da Meta; nos demais canais o caminho de sempre segue.
  def inbox_oficial?
    @follow_up.conversation&.inbox&.channel_type == Crm::FollowUps::EnvioForaDaJanela::CANAL_OFICIAL
  end

  # Havia candidatos e a composição não deu mensagem: a 2ª chamada em texto livre pelo Híbrido (chat#1349).
  def recompor_em_texto_livre(composition)
    return composition unless hybrid_free_form_retry?(composition)

    switch_to_hybrid_free_form('template_declined')
    compose
  end

  # Mensagem de modelo enviada pelo ponto único: grava o registro append-only (#1585). Nunca levanta; a mensagem já saiu.
  def registrar_envio_fora_da_janela(message)
    registro = base_metadata['envio_fora_da_janela']
    return if message.blank? || registro.blank?

    Whatsapp::Templates::EnvioForaDaJanela.registrar_envio(message: message, registro: registro.merge('crm_follow_up_id' => @follow_up.id))
  end
end
