# #3101: da primeira campanha, o que a varredura do reenvio precisa saber (CampaignJourney::Reenvio::Varredura).
# - `terminou?`: o envio acabou — a campanha saiu toda, ninguém espera na fila (limite, horário, melhor horário) e, com
#   duas versões, o resto já foi;
# - `cancelada?`: a pessoa cancelou a primeira (WhatsApp API e e-mail; a do WhatsApp Oficial e do SMS só se apaga);
# - `fim`: o último envio (nil = ninguém recebeu);
# - `contact_ids`: quem recebe a segunda — quem recebeu, menos quem respondeu (a marca do CampaignJourney::ReplyMarker,
#   lida pelo CampaignJourney::ResultReplies), menos quem leu (só no `nao_leu`, D2: WhatsApp Oficial), menos quem pediu
#   para não receber ou foi bloqueado (Contact.campaign_reachable). O grupo de controle da F2 nunca recebeu a primeira,
#   então nunca entra.
class CampaignJourney::Reenvio::QuemRecebe
  # Os destinatários que receberam, em cada lugar onde o canal os guarda.
  RECEBERAM = {
    'Campaign' => %w[sent delivered read],
    'WhatsappApiCampaign' => %w[sent],
    'EmailCampaign' => %w[sent delivered opened clicked]
  }.freeze

  def initialize(campanha, quem)
    @campanha = campanha
    @quem = quem
  end

  def terminou?
    saiu_toda? && !CampaignJourney::DuasVersoes.para(@campanha).esperando_o_resto?
  end

  def cancelada?
    case @campanha
    when WhatsappApiCampaign then @campanha.cancelled?
    when EmailCampaign then @campanha.canceled?
    else false
    end
  end

  def fim
    destinatarios.maximum(:sent_at)
  end

  def contact_ids
    ids = receberam.where.not(contact_id: nil).distinct.pluck(:contact_id) - responderam
    return [] if ids.empty?

    @campanha.account.contacts.where(id: ids).campaign_reachable.pluck(:id)
  end

  private

  def saiu_toda?
    case @campanha
    when WhatsappApiCampaign then @campanha.terminal? && !@campanha.cancelled? && !destinatarios.pending.exists?
    when EmailCampaign then @campanha.sent? || @campanha.failed?
    else @campanha.completed? && !destinatarios.queued.exists?
    end
  end

  def destinatarios
    CampaignJourney::ComprasDaCampanha.recipients_de(@campanha)
  end

  def receberam
    recebidos = destinatarios.where(status: RECEBERAM.fetch(@campanha.class.name))
    @quem == CampaignJourney::Reenvio::NAO_LEU ? recebidos.where(read_at: nil) : recebidos
  end

  def responderam
    CampaignJourney::ResultReplies.new(@campanha.account, CampaignJourney::CampaignMarks.source_id_for(@campanha)).contact_ids
  end
end
