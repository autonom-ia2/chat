# #3099: manda o resto do público depois da escolha da versão (CampaignJourney::EnviarRestoJob), pelo mesmo caminho do
# envio original de cada canal. Pode rodar de novo sem mandar duas vezes: cada canal só cria quem ainda não está na lista.
# - WhatsApp Oficial e SMS: a campanha já rodou (o teste) e segue `completed`; o serviço do canal cria os destinatários
#   do resto e manda (#enviar_resto, nos módulos do envio da jornada). Ainda saindo ou parada (CampaignPause): espera e
#   tenta de novo;
# - WhatsApp API: o resolvedor cria os destinatários do resto; se a campanha já tinha terminado, volta a `running`;
# - E-mail: os destinatários do resto já estão na lista, esperando (EmailCampaigns::RitmoDoDestinatario); o motor volta
#   a andar e os manda.
# A versão de cada pessoa sai de campaign_version_contacts (o resto ganhou a escolhida em DuasVersoes#mandar_resto!).
class CampaignJourney::DuasVersoes::EnvioDoResto
  ESPERA_SE_PARADA = 15.minutes

  def initialize(link)
    @link = link
  end

  def enviar!
    campaign = @link.campaign
    case campaign
    when EmailCampaign then email(campaign)
    when WhatsappApiCampaign then whatsapp_api(campaign)
    when Campaign then chatwoot(campaign)
    end
  end

  private

  # Escolhida antes de a campanha sair (`active`): o disparo normal já manda todo mundo, cada um com a sua versão. Ainda
  # saindo (o teste) ou parada: tenta de novo depois.
  def chatwoot(campaign)
    servico = CampaignJourney::RetomarAdiadosJob::SERVICOS[campaign.inbox&.inbox_type]&.constantize&.new(campaign: campaign)
    return if campaign.active? || !servico.respond_to?(:enviar_resto)
    return CampaignJourney::EnviarRestoJob.set(wait: ESPERA_SE_PARADA).perform_later(@link.id) if campaign.processing? || parada?(campaign)

    servico.enviar_resto
  end

  def parada?(campaign)
    CampaignPause.in_effect.exists?(pausable_type: 'Campaign', pausable_id: campaign.id)
  end

  def whatsapp_api(campaign)
    andar = campaign.with_lock do
      next false if campaign.scheduled? || campaign.cancelled? || campaign.failed?

      WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
      terminou = campaign.completed? || campaign.completed_with_failures?
      next false unless terminou && campaign.whatsapp_api_campaign_recipients.pending.exists?

      campaign.update!(status: :running, completed_at: nil)
    end
    WhatsappApiCampaigns::DeliveryJob.perform_later(campaign.id) if andar
  end

  def email(campaign)
    EmailCampaigns::DeliveryJob.perform_later(campaign.id) if campaign.sending?
  end
end
