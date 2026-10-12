# Se "Retomar" já vai passar (#1332): o modelo da campanha está aprovado de novo e igual ao que ela guardou. Usa a
# conferência do disparo (`Whatsapp::Templates::DispatchCheck`) só com a lista guardada (`lookup: false`), sem chamar a
# Meta por campanha; ao retomar, o disparo pergunta à Meta de novo.
#
# A lista guardada é por caixa, e caixas da mesma conta do WhatsApp (WABA) dividem os modelos: vale a lista sincronizada
# mais recente entre elas (a tela de Modelos sincroniza por uma caixa só do grupo).
class CampaignPauses::ResumeReadiness
  def initialize(account)
    @account = account
    @channels = {}
  end

  def ready?(campaign)
    # Campanha sem modelo não parou por modelo: nada a conferir.
    return true if campaign.template_params.blank?

    channel = freshest_channel(campaign.inbox&.channel)
    return false unless channel

    Whatsapp::Templates::DispatchCheck.new(campaign, channel: channel, lookup: false).call.ok?
  end

  private

  def freshest_channel(channel)
    return channel unless channel.is_a?(Channel::Whatsapp) && channel.waba_id.present?

    @channels[channel.waba_id] ||=
      Channel::Whatsapp.where(account_id: @account.id).where("provider_config ->> 'business_account_id' = ?", channel.waba_id)
                       .where.not(message_templates_last_updated: nil).order(message_templates_last_updated: :desc).first || channel
  end
end
