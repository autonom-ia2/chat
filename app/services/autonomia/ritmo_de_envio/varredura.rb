# A cada rodada (#3063, item 2): devolve ao envio os destinatários de campanha cujo adiamento venceu e apaga do contador
# o que já não entra em período nenhum. Cada motor sabe retomar o seu:
# - WhatsApp Oficial e SMS: CampaignJourney::RetomarAdiadosJob (a campanha já terminou a primeira rodada);
# - WhatsApp API: o DeliveryJob da campanha, que segue `running` enquanto alguém espera;
# - e-mail: o DeliveryJob da campanha, que segue `sending` enquanto alguém espera (SES ou caixa direta).
class Autonomia::RitmoDeEnvio::Varredura
  # O maior período escolhível, mais uma folga.
  GUARDA = (Autonomia::RitmoDeEnvio::Config::DIAS.max + 1).days
  APAGA_EM_LOTES_DE = 5_000

  def self.rodar(agora: Time.current)
    new(agora).rodar
  end

  def initialize(agora)
    @agora = agora
  end

  def rodar
    whatsapp_e_sms.each { |id| CampaignJourney::RetomarAdiadosJob.perform_later(id) }
    whatsapp_api.each { |id| WhatsappApiCampaigns::DeliveryJob.perform_later(id) }
    email.each { |id| EmailCampaigns::DeliveryJob.perform_later(id) }
    apagar_contador_velho
  end

  private

  def vencidos(destinatarios, coluna)
    destinatarios.where(adiado_ate: ..@agora).distinct.pluck(coluna)
  end

  # CampaignRecipient é do Enterprise; sem ele, a campanha do Chatwoot não guarda destinatário e não adia ninguém.
  def whatsapp_e_sms
    return [] unless defined?(CampaignRecipient)

    vencidos(CampaignRecipient.queued, :campaign_id)
  end

  # Só a campanha cuja corrente parou (todo pendente está adiado): com alguém pendente sem adiamento a corrente segue
  # viva e pega o vencido sozinha; um DeliveryJob a mais dobraria o ritmo da caixa.
  def whatsapp_api
    ids = vencidos(WhatsappApiCampaignRecipient.pending, :whatsapp_api_campaign_id)
    andando = WhatsappApiCampaignRecipient.pending.where(whatsapp_api_campaign_id: ids, adiado_ate: nil)
                                          .distinct.pluck(:whatsapp_api_campaign_id)
    WhatsappApiCampaign.running.where(id: ids - andando).pluck(:id)
  end

  def email
    ids = vencidos(EmailCampaignRecipient.pending, :email_campaign_id)
    EmailCampaign.sending.where(id: ids).pluck(:id)
  end

  def apagar_contador_velho
    Autonomia::EnvioAoCliente.where(enviado_em: ...(@agora - GUARDA)).in_batches(of: APAGA_EM_LOTES_DE).delete_all
  end
end
