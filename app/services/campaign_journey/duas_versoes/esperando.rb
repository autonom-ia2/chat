# #3099 (D5): as campanhas da conta cujo teste terminou no "eu escolho" e esperam alguém escolher a versão do resto.
# A lista de Campanhas avisa; depois de PRAZO_DO_EU_ESCOLHO, a versão 1 vai sozinha (CampaignJourney::DuasVersoes::Escolha).
# Também as campanhas em que, passada a espera, ninguém do teste recebeu (CampaignJourney::DuasVersoes::SemEnvio):
# alguém precisa olhar (canal desligado, campanha parada), senão a versão 1 vai para o resto depois de PRAZO_SEM_ENVIO.
#
#   [{ motivo: 'escolher' | 'sem_envio', channel, id, name, resto, vai_sozinha_em (epoch) }] — `channel` e `id` são os
#   do resultado da campanha (CampaignJourney::ResultFinder: display_id nas campanhas do Chatwoot, id no e-mail e na
#   WhatsApp API).
class CampaignJourney::DuasVersoes::Esperando
  LIMITE = 50

  def initialize(account)
    @account = account
  end

  def payload
    esperando = links.where(teste_estado: 'esperando_voce').order(:teste_escolhe_em).limit(LIMITE)
    escolher = esperando.filter_map do |link|
      vai_em = link.teste_escolhe_em && (link.teste_escolhe_em + CampaignJourney::DuasVersoes::PRAZO_DO_EU_ESCOLHO)
      linha(link, 'escolher', vai_em)
    end
    escolher + sem_envio
  end

  private

  def links
    CampaignAudienceLink.where(account_id: @account.id).includes(:campaign)
  end

  # Sem envio, o cron não grava a hora de escolher: só os testando sem ela.
  def sem_envio
    links.where(teste_estado: 'testando', teste_escolhe_em: nil).order(:id).limit(LIMITE).filter_map do |link|
      sem_envio = CampaignJourney::DuasVersoes::SemEnvio.new(link)
      linha(link, 'sem_envio', sem_envio.ate) if sem_envio.avisar?
    end
  end

  def linha(link, motivo, vai_em)
    canal, id, nome = endereco(link.campaign)
    return if canal.nil?

    { motivo: motivo, channel: canal, id: id, name: nome, resto: link.teste_resto, vai_sozinha_em: vai_em&.to_i }
  end

  def endereco(campaign)
    case campaign
    when EmailCampaign then [CampaignJourney::ResultFinder::EMAIL, campaign.id, campaign.name]
    when WhatsappApiCampaign then [CampaignJourney::ResultFinder::WHATSAPP_API, campaign.id, campaign.title]
    when Campaign then [CampaignJourney::ResultFinder.channel_of(campaign), campaign.display_id, campaign.title]
    end
  end
end
