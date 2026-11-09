# A campanha de e-mail com lista (G52, #2760) vai para quem está na lista na hora do envio: agendar, mandar agora e o
# agendador montam os destinatários de novo antes de conferir se a campanha pode sair. Molde:
# CampaignJourney::EmailAudienceGate (o público salvo). Prependido por config/initializers/email_lists.rb; campanha sem
# lista passa direto.
#
# A montagem roda dentro das travas do envio (conta, reputação, campanha), antes da conferência do motor
# (`sendable?`). Não há trava da lista: pôr e tirar a etiqueta não espera o envio, e quem entrar depois da montagem fica
# para a próxima campanha.
module EmailLists::Gate
  def self.sync!(campaign)
    EmailLists::Recipients.new(campaign).sync!
  end

  # EmailCampaign: mandar agora (claim_for_sending!) e agendar (schedule!) montam a lista antes.
  module Campaign
    def claim_for_sending!
      return super if email_list_id.blank?

      with_delivery_lock do
        EmailLists::Gate.sync!(self)
        super
      end
    end

    def schedule!(scheduled_at:)
      return super if email_list_id.blank?

      with_delivery_lock do
        EmailLists::Gate.sync!(self)
        super
      end
    end

    # Antes da primeira montagem a campanha ainda não tem destinatário: vale ter alguém na lista que receberia. A
    # conferência de dentro do claim/schedule roda depois da montagem.
    # Depois da montagem, só pendente conta: a lista em que todos estão bloqueados (só `suppressed`) não sai com zero
    # envios.
    def sendable_recipients?
      return super if email_list_id.blank?
      return EmailLists::Recipients.new(self).candidatos? unless email_campaign_recipients.exists?

      email_campaign_recipients.pending.exists? && super
    end
  end

  # EmailCampaigns::Scheduler: a campanha com lista vencida monta a lista antes das conferências de higiene e de
  # reputação. Se entrou alguém, os endereços novos ganham a checagem e o envio espera o próximo ciclo (em vez de pausar
  # a campanha); com a higiene em modo enforce, espera enquanto houver pendente sem checagem.
  module Scheduler
    LISTA_VAZIA = 'email_list_empty'.freeze

    private

    def start(campaign)
      return super if campaign.email_list_id.blank?
      return if esperar_a_lista?(campaign)

      super
    end

    def esperar_a_lista?(campaign)
      adicionados = campaign.with_delivery_lock { montar_a_lista(campaign) }
      return true if adicionados.nil? || adicionados.positive?

      lista_aguardando_checagem?(campaign)
    # Como o rescue do próprio Scheduler: a campanha que não consegue montar a lista falha com o erro limpo, em vez de
    # ficar agendada tentando para sempre.
    rescue StandardError => e
      safe_message = EmailCampaigns::SafeErrorMessage.call(e.message)
      Rails.logger.error("[EmailLists::Gate] campaign=#{campaign.id} #{e.class.name}: #{safe_message}")
      campaign.with_delivery_lock do
        campaign.update(status: :failed, last_error: safe_message) if campaign.scheduled? || campaign.sending?
      end
      true
    end

    # Quantos entraram, ou nil quando a campanha falhou: a lista que esvaziou entre o agendamento e a hora do envio
    # (todos saíram, ou só sobrou quem está bloqueado) não sai com zero envios, e a campanha falha com o motivo gravado
    # em vez de virar "enviada" para ninguém. Roda sob a trava de envio.
    def montar_a_lista(campaign)
      campaign.reload
      return 0 unless campaign.scheduled?

      added = EmailLists::Gate.sync!(campaign)[:added]
      return added if added.positive? || campaign.delivery_history? || campaign.email_campaign_recipients.pending.exists?

      campaign.update!(status: :failed, last_error: LISTA_VAZIA)
      nil
    end

    def lista_aguardando_checagem?(campaign)
      return false unless EmailCampaigns::HygieneConfig.new.enforce?

      sem_checagem = campaign.email_campaign_recipients.pending.where.not(contact_id: nil).exists?(preflight_status: 'unchecked')
      EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id) if sem_checagem
      sem_checagem
    end
  end

  # EmailCampaigns::Presentation::SendReadiness: antes da primeira montagem, a revisão conta quem está na lista.
  module Readiness
    private

    def send_checks(eligible)
      checks = super
      return checks if checks[:recipients] || @campaign.email_list_id.blank? || @campaign.email_campaign_recipients.exists?

      checks.merge(recipients: EmailLists::Recipients.new(@campaign).candidatos?)
    end
  end
end
