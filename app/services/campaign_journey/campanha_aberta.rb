# Campanha de e-mail aberta (#2717, decisão do Rodrigo de 08/11): a lista segue o Público depois do primeiro envio.
# Quem entra depois também recebe, uma vez; quem sai antes do envio não recebe. A régua é a de sempre
# (CampaignJourney::EmailAudienceRecipients: recusa de mensagem, supressão; checagem de higiene; DeliveryClaim no
# envio). A campanha aberta não fecha sozinha em "enviada": segue enviando até alguém cancelar.
#
# Quem entra no meio só vai ao envio depois de conferido pela checagem de higiene: os motores leem a lista por
# `a_enviar`, que na aberta deixa de fora o pendente ainda sem conferir. Assim a régua "exigir" não pausa a
# campanha por causa de quem acabou de chegar, e nenhuma régua manda antes da conferência.
module CampaignJourney::CampanhaAberta
  module_function

  SEM_CONFERIR = 'unchecked'.freeze
  # Espera do envio de novo quando o lote terminou antes de alcançar quem chegou no meio.
  NOVA_RODADA = 30.seconds

  # Põe na lista quem entrou no Público e tira o pendente de quem saiu. Chamado pela própria linha do público, ao entrar,
  # sair ou mudar (CampaignImportRow → CampaignJourney::CampanhaAbertaSyncJob), venha ela de quem vier.
  # Corre junto com o envio sem perigo: roda dentro das travas de entrega, e o envio só reserva a pessoa com um UPDATE
  # condicional de pending para sent (EmailCampaigns::DeliveryClaim#claim). Pendente apagado antes da reserva não
  # sai; reservado já não é pending e o sync não toca. Tirar depois do envio não desfaz o e-mail.
  # => { added:, removed: }
  def sincronizar!(campaign)
    return { added: 0, removed: 0 } unless campaign.aberta?

    CampaignJourney::EmailAudienceGate.with_audience_locks(campaign) do
      CampaignJourney::EmailAudienceGate.sync!(campaign.reload)
    end
  end

  # O que os motores de envio leem. Na fechada, todo pendente, como sempre.
  def a_enviar(campaign)
    pendentes = campaign.email_campaign_recipients.pending
    campaign.aberta? ? pendentes.where.not(preflight_status: SEM_CONFERIR) : pendentes
  end

  # Fim de uma passada da checagem de higiene. Quem chegou durante a passada ficou de fora dela (o teto é o maior id
  # do começo): abre outra. A passada viva, se houver, chama aqui de novo ao terminar. Só "sem conferir" reabre: um
  # resultado vencido (DNS com validade curta) não roda passada atrás de passada. Com todos conferidos, acorda o envio.
  def depois_da_checagem(campaign)
    campaign.reload
    return unless campaign.aberta? && campaign.sending?
    return EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id) if sem_conferir?(campaign)

    acordar_envio(campaign) if a_enviar(campaign).exists?
  end

  # Fim de um lote do motor SES. Quem foi conferido enquanto o lote rodava pode ter ficado depois do último que ele
  # viu, e o DeliveryJob que a checagem pediu caiu na trava ocupada deste lote: volta daqui a pouco para eles.
  def depois_do_lote(campaign, ultimo_visto)
    return unless campaign.aberta? && campaign.reload.sending?
    return unless a_enviar(campaign).exists?(['id > ? AND attempts = 0', ultimo_visto])

    EmailCampaigns::DeliveryJob.set(wait: NOVA_RODADA).perform_later(campaign.id)
  end

  def sem_conferir?(campaign)
    campaign.email_campaign_recipients.pending.exists?(preflight_status: SEM_CONFERIR)
  end

  # No envio pela caixa, uma cadeia de ticks já agendada pega quem chegou: outra cadeia furaria o ritmo humano.
  # Não é garantia: entre um tick apagar a marca da cadeia e agendar o próximo, esta leitura (fora da trava) vê a marca
  # vazia e abre outra cadeia. As duas convergem em uma (#2722), com no máximo um e-mail fora do ritmo.
  def acordar_envio(campaign)
    return if campaign.direct_inbox? && EmailCampaigns::DirectInbox::DeliveryEngine.tick_scheduled?(campaign)

    EmailCampaigns::DeliveryJob.perform_later(campaign.id)
  end
end
