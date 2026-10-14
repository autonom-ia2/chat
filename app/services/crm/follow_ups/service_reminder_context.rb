# Lembrete de Atender (#1498) no CallbackRunner: não há fala do cliente a citar (o motivo é a data ou o andamento),
# então não passa pela prova de citação; os fatos (assunto, valor, vencimento, promessa, hoje) vêm do card, nunca da IA.
module Crm::FollowUps::ServiceReminderContext
  # Sem modelo pronto e com o Híbrido pronto: o CallbackRunner segue para o texto livre, como no retorno combinado.
  TEXTO_LIVRE_HIBRIDO = :texto_livre_hibrido

  private

  # Fora das 24h (#1498): o EnvioForaDaJanela acha o modelo aprovado e monta os campos; o envio é o de sempre
  # (MessageSender -> template_params do upstream). Sem modelo pronto, vira lembrete para a equipe, nada ao cliente.
  def lembrete_fora_da_janela?
    service_reminder? && !messaging_window.can_send_session_message?
  end

  # nil: o CallbackRunner segue o caminho de sempre (dentro da janela, ou texto livre pelo Híbrido).
  def entrega_do_lembrete_fora_da_janela
    return unless lembrete_fora_da_janela?

    entrega = entregar_fora_da_janela
    entrega unless entrega == TEXTO_LIVRE_HIBRIDO
  end

  # Antes do modelo, a mesma leitura da conversa decide se ainda faz sentido: "já paguei", "já resolveu" ou "não
  # preciso mais" param aqui, como no caminho com texto livre.
  def entregar_fora_da_janela
    envio = Crm::FollowUps::EnvioForaDaJanela.new(follow_up: @follow_up, card: @card).call
    unless envio.enviar?
      return TEXTO_LIVRE_HIBRIDO if messaging_window.hybrid_web_available?

      return self.class::Result.fallback(envio.motivo)
    end

    @send_mode = :free_form
    @candidates = []
    return self.class::Result.fallback('closure') if closure?(compose)

    @follow_up.update!(metadata: base_metadata.merge(envio.metadata))
    @send_mode = :choose_template
    return self.class::Result.failed('marketing_cap', @now + self.class::MARKETING_CAP_WINDOW) if capped?

    deliver
  end

  # O lembrete nunca usa modelo genérico da lista (só o da finalidade, pelo Garantir).
  def callback_template_candidates
    service_reminder? ? [] : template_candidates
  end

  def service_reminder?
    base_metadata['source'] == Crm::FollowUps::ServiceReminderScheduler::SOURCE
  end

  # O que o composer recebe: os fatos do lembrete, ou o pedido de retorno do cliente.
  def composer_context
    return service_context if service_reminder?

    { 'requested_at_text' => base_metadata['requested_at_text'], 'requested_at' => @follow_up.due_at&.iso8601 }
  end

  def service_context
    {
      'kind' => base_metadata['kind'].to_s,
      'subject' => @card.title.to_s,
      'amount' => service_amount,
      'due_date' => @card.expected_close_at&.utc&.to_date&.iso8601,
      'promised_date' => @card.metadata.to_h['payment_promise_at'].presence,
      'today' => @now.in_time_zone(@follow_up.timezone).to_date.iso8601
    }.compact
  end

  def service_amount
    return unless @card.value_cents.to_i.positive?

    TemplateFields::Format.money_cents(@card.value_cents, @card.currency.presence || 'BRL')
  end
end
