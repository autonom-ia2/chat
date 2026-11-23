# #3099: manda o resto do público depois da escolha da versão (CampaignJourney::EnviarRestoJob), pelo mesmo caminho do
# envio original de cada canal. Pode rodar de novo sem mandar duas vezes: cada canal só cria quem ainda não está na lista.
# - WhatsApp Oficial e SMS: a campanha já rodou (o teste) e segue `completed`; o serviço do canal cria os destinatários
#   do resto e manda (#enviar_resto, nos módulos do envio da jornada). Ainda saindo, parada (CampaignPause) ou com a
#   retomada dos adiados rodando (CampaignJourney::EnvioSozinho, a mesma trava): espera e tenta de novo;
# - WhatsApp API: o resolvedor cria os destinatários do resto. Se a campanha já tinha terminado, volta a `running` e a
#   corrente de envio (WhatsappApiCampaigns::DeliveryJob) recomeça. Se ainda está `running`, a corrente viva pega o resto
#   sozinha; parada (só adiados esperando, ou terminando sem ver o resto), recomeça. Nunca duas correntes: um
#   DeliveryJob a mais dobraria o ritmo da caixa (Autonomia::RitmoDeEnvio::Varredura);
# - E-mail: os destinatários do resto já estão na lista, esperando (EmailCampaigns::RitmoDoDestinatario); o motor volta
#   a andar e os manda.
# A versão de cada pessoa sai de campaign_version_contacts (o resto ganhou a escolhida em DuasVersoes#mandar_resto!).
class CampaignJourney::DuasVersoes::EnvioDoResto
  ESPERA_SE_PARADA = 15.minutes
  ESPERA_SE_OCUPADA = 1.minute

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
    return de_novo(ESPERA_SE_PARADA) if campaign.processing? || parada?(campaign)

    de_novo(ESPERA_SE_OCUPADA) unless CampaignJourney::EnvioSozinho.sozinho(campaign) { servico.enviar_resto }
  end

  def de_novo(espera)
    CampaignJourney::EnviarRestoJob.set(wait: espera).perform_later(@link.id)
  end

  def parada?(campaign)
    CampaignPause.in_effect.exists?(pausable_type: 'Campaign', pausable_id: campaign.id)
  end

  # Na trava da campanha, a mesma do fim da corrente (DeliveryEngine#finish_campaign!): ou a corrente terminou antes
  # (a campanha está `completed` e volta a andar aqui), ou ela termina depois e vê o resto pendente.
  def whatsapp_api(campaign)
    andar = campaign.with_lock do
      next false if campaign.scheduled? || campaign.cancelled? || campaign.failed?

      corrente_parada = !mandando_agora?(campaign)
      WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
      next false unless mandando_agora?(campaign)
      next campaign.running? && corrente_parada unless campaign.completed? || campaign.completed_with_failures?

      campaign.update!(status: :running, completed_at: nil)
    end
    WhatsappApiCampaigns::DeliveryJob.perform_later(campaign.id) if andar
  end

  # Alguém saindo ou pendente para agora: a corrente está viva (ou, sem ela, há o que mandar).
  def mandando_agora?(campaign)
    destinatarios = campaign.whatsapp_api_campaign_recipients
    destinatarios.sending.exists? || destinatarios.pending.exists?(['adiado_ate IS NULL OR adiado_ate <= ?', Time.current])
  end

  def email(campaign)
    EmailCampaigns::DeliveryJob.perform_later(campaign.id) if campaign.sending?
  end
end
