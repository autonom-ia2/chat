# #3098: "Quem comprou depois" da campanha de e-mail da jornada (a janela de compra e o grupo de controle). O link do
# e-mail nasce no Passo 2, antes da revisão, e o envio final vai pela tela de e-mail (send_now/schedule); por isso a
# revisão grava as escolhas aqui, logo antes de agendar ou enviar, e o grupo é sorteado na hora.
#
#   PUT …/campaign_journey/email_medicoes/:id  { janela_de_compra_dias, grupo_de_controle_pct, duas_versoes }
#
# #3099: `duas_versoes` ({ criterio, divisao, espera_horas, segunda: { subject } }) liga as duas versões do e-mail (D2:
# só o assunto muda). Sem a chave, a campanha fica sem duas versões (a revisão manda o estado inteiro a cada vez).
#
# Quem pode enviar a campanha de e-mail (EmailCampaignPolicy#send_now?). Só antes do envio (draft ou agendada sem
# ninguém enviado): depois disso o público já recebeu e o grupo não muda. CAMPAIGN_JOURNEY_ENABLED off → 404.
class Api::V1::Accounts::CampaignJourney::EmailMedicoesController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled

  def update
    campaign = EmailCampaign.where(account_id: Current.account.id).find(params[:id])
    authorize campaign, :send_now?
    link = CampaignAudienceLink.for_campaign(campaign)
    raise ActiveRecord::RecordNotFound if link.nil?
    return render json: { error: 'campaign_journey.already_sent' }, status: :unprocessable_entity unless aplicar(campaign, link)

    head :no_content
  rescue ::CampaignJourney::DuasVersoes::Invalida => e
    render json: { error: 'campaign_journey.invalid_duas_versoes', code: e.code }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'campaign_journey.invalid_medicao', message: e.record.errors.full_messages.to_sentence },
           status: :unprocessable_entity
  end

  private

  def antes_do_envio?(campaign)
    (campaign.draft? || campaign.scheduled?) && !campaign.email_campaign_recipients.where.not(sent_at: nil).exists?
  end

  # Trava a linha do público, a mesma que o envio trava antes de sincronizar a lista (CampaignJourney::EmailAudienceGate),
  # e só então confere que a campanha não começou a sair: o sorteio e a lista do envio nunca se cruzam. false = já saiu.
  def aplicar(campaign, link)
    ActiveRecord::Base.transaction do
      link.campaign_import&.lock!
      next false unless antes_do_envio?(campaign.reload)

      escolhas = params.permit(:janela_de_compra_dias, :grupo_de_controle_pct)
      ::CampaignJourney::Medicao.new(link).aplicar!(escolhas, duas_versoes: duas_versoes, segunda: segunda(campaign)) do
        ::CampaignJourney::Medicao.publico(link, 'email')
      end
      true
    end
  end

  def duas_versoes
    params.permit(duas_versoes: [:criterio, :divisao, :espera_horas, { segunda: [:subject] }]).to_h[:duas_versoes].presence
  end

  def segunda(campaign)
    return if duas_versoes.nil?

    ::CampaignJourney::DuasVersoes.conferir!(duas_versoes)
    ::CampaignJourney::DuasVersoes::Segunda.email(duas_versoes[:segunda].to_h, primeiro: campaign.subject)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end
