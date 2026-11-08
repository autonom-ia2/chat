# #2717: alguém entrou, saiu ou mudou no público (CampaignImportRow). Cada campanha de e-mail aberta ligada a ele, enviando
# ou pausada, sincroniza a lista: quem entrou recebe pela régua de sempre, o pendente de quem saiu é apagado.
#
# Um job por público a cada janela, não um por linha: a planilha grava linha a linha (create!), e 20 mil linhas não
# podem virar 20 mil jobs nem 20 mil sincronizações. A marca no Redis junta as mudanças até o job rodar; ele a apaga
# antes de ler o público, então a linha gravada depois da leitura marca de novo e agenda o próximo.
class CampaignJourney::CampanhaAbertaSyncJob < ApplicationJob
  queue_as :low

  MARCA = 'campaign_journey:campanha_aberta:sync:%<campaign_import_id>d'.freeze
  # Tempo para juntar as linhas de uma mesma gravação.
  JANELA = 5.seconds
  # A marca some sozinha se o job se perder: a próxima mudança depois disso agenda outro.
  MARCA_VALE = 2.minutes

  def self.agendar(campaign_import_id)
    return unless EmailCampaigns::Config.enabled?
    return unless Redis::Alfred.set(marca(campaign_import_id), 1, nx: true, ex: MARCA_VALE.to_i)

    set(wait: JANELA).perform_later(campaign_import_id)
  end

  def self.marca(campaign_import_id) = format(MARCA, campaign_import_id: campaign_import_id)

  def perform(campaign_import_id)
    Redis::Alfred.delete(self.class.marca(campaign_import_id))
    return unless EmailCampaigns::Config.enabled?

    campanhas_abertas(campaign_import_id).find_each { |campanha| CampaignJourney::CampanhaAberta.sincronizar!(campanha) }
  end

  private

  def campanhas_abertas(campaign_import_id)
    ligadas = CampaignAudienceLink.where(campaign_type: EmailCampaign.name, campaign_import_id: campaign_import_id).select(:campaign_id)
    EmailCampaign.where(id: ligadas, aberta: true, status: %i[sending paused])
  end
end
