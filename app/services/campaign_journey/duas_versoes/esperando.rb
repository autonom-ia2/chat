# #3099 (D5): as campanhas da conta cujo teste terminou no "eu escolho" e esperam alguém escolher a versão do resto.
# A lista de Campanhas avisa; depois de PRAZO_DO_EU_ESCOLHO, a versão 1 vai sozinha (CampaignJourney::DuasVersoes::Escolha).
#
#   [{ channel, id, name, resto, vai_sozinha_em (epoch) }] — `channel` e `id` são os do resultado da campanha
#   (CampaignJourney::ResultFinder: display_id nas campanhas do Chatwoot, id no e-mail e na WhatsApp API).
class CampaignJourney::DuasVersoes::Esperando
  LIMITE = 50

  def initialize(account)
    @account = account
  end

  def payload
    links = CampaignAudienceLink.where(account_id: @account.id, teste_estado: 'esperando_voce').includes(:campaign)
                                .order(:teste_escolhe_em).limit(LIMITE)
    links.filter_map { |link| linha(link) }
  end

  private

  def linha(link)
    campaign = link.campaign
    canal, id, nome = endereco(campaign)
    return if canal.nil?

    vai_em = link.teste_escolhe_em && (link.teste_escolhe_em + CampaignJourney::DuasVersoes::PRAZO_DO_EU_ESCOLHO)
    { channel: canal, id: id, name: nome, resto: link.teste_resto, vai_sozinha_em: vai_em&.to_i }
  end

  def endereco(campaign)
    case campaign
    when EmailCampaign then [CampaignJourney::ResultFinder::EMAIL, campaign.id, campaign.name]
    when WhatsappApiCampaign then [CampaignJourney::ResultFinder::WHATSAPP_API, campaign.id, campaign.title]
    when Campaign then [CampaignJourney::ResultFinder.channel_of(campaign), campaign.display_id, campaign.title]
    end
  end
end
