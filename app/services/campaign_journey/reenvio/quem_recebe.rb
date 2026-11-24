# #3101: da primeira campanha, o que a varredura do reenvio precisa saber (CampaignJourney::Reenvio::Varredura).
# - `terminou?`: o envio acabou — a campanha saiu toda, ninguém espera na fila (limite, horário, melhor horário) e, com
#   duas versões, o resto já foi;
# - `cancelada?`: a pessoa cancelou a primeira (WhatsApp API e e-mail; a do WhatsApp Oficial e do SMS só se apaga);
# - `fim`: o último envio (nil = ninguém recebeu);
# - `contact_ids`: quem recebe a segunda — quem recebeu, menos quem respondeu, menos quem leu (só no `nao_leu`, D2:
#   WhatsApp Oficial), menos quem pediu para não receber ou foi bloqueado (Contact.campaign_reachable). O grupo de
#   controle da F2 nunca recebeu a primeira, então nunca entra.
#
# "Respondeu" é a regra do CampaignJourney::ReplyMarker — mensagem do cliente na caixa da campanha depois do envio —,
# sem o teto de 72 h da marca: a segunda pode sair até 7 dias depois, e quem escreveu no quinto dia também respondeu.
# Conta a marca da campanha (CampaignJourney::ResultReplies) e qualquer mensagem do cliente nas caixas das respostas
# desde o primeiro envio.
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
    ids = receberam.where.not(contact_id: nil).distinct.pluck(:contact_id) - marcados
    ids -= escreveram_depois(ids)
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

  def marcados
    CampaignJourney::ResultReplies.new(@campanha.account, CampaignJourney::CampaignMarks.source_id_for(@campanha)).contact_ids
  end

  # Destes contatos, quem mandou mensagem numa caixa das respostas desde o primeiro envio.
  def escreveram_depois(ids)
    inicio = destinatarios.minimum(:sent_at)
    caixas = caixas_das_respostas
    return [] if ids.empty? || inicio.nil? || caixas.empty?

    Message.incoming.where(account_id: @campanha.account_id, inbox_id: caixas).where('messages.created_at >= ?', inicio)
           .joins(:conversation).where(conversations: { contact_id: ids }).distinct.pluck('conversations.contact_id')
  end

  # Onde as respostas chegam: a caixa da campanha; no e-mail, a caixa das respostas escolhida, a do domínio ou a caixa
  # que manda (a mesma ordem do CampaignJourney::ReplyMarker).
  def caixas_das_respostas
    return [@campanha.inbox_id].compact unless @campanha.is_a?(EmailCampaign)

    [@campanha.reply_to_inbox_id, @campanha.sender_identity&.reply_to_inbox_id,
     (@campanha.sender_inbox_id if @campanha.direct_inbox?)].compact.uniq
  end
end
