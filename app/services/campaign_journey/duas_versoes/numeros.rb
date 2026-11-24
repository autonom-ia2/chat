# #3099: os números de cada versão no teste — quem recebeu, quem respondeu e quem comprou —, para o resultado da
# campanha e para a escolha automática da vencedora (CampaignJourney::DuasVersoes::Escolha).
#
# Contam só as pessoas do teste (no público pequeno, todo mundo): o resto recebeu a versão escolhida e não compara.
# - Receberam: tem envio desta campanha (sent_at). No WhatsApp Oficial, quem recebeu a mensagem escrita da conversa
#   aberta (#1335) fica de fora: não recebeu nenhuma das duas versões;
# - Responderam: a conversa ganhou a marca da campanha (CampaignJourney::ResultReplies, até 72 h depois do envio);
# - Compraram: a régua de compras da F2 (CampaignJourney::ComprasDaCampanha: a janela da campanha e a campanha mais
#   recente), só com o CRM ligado.
class CampaignJourney::DuasVersoes::Numeros
  def initialize(link, account:)
    @link = link
    @campaign = link.campaign
    @account = account
  end

  # O primeiro envio da campanha: o começo do teste.
  def primeiro_envio
    CampaignJourney::ComprasDaCampanha.recipients_de(@campaign).where.not(sent_at: nil).minimum(:sent_at)
  end

  # [{ receberam:, responderam:, compraram:, valor: }, { … }] da versão 1 e da versão 2. `pipeline_ids`: nil = todos
  # os funis; `com_valor`: o dinheiro das compras por moeda (nil sem a permissão de ver valor de venda).
  def por_versao(pipeline_ids: nil, com_valor: false)
    compras = compras_por_versao(pipeline_ids)
    CampaignJourney::DuasVersoes::VERSOES.map do |versao|
      quem = recebeu.select { |_contato, sua| sua == versao }.keys.to_set
      da_versao = compras.select { |compra| quem.include?(compra[:contato]) }
      { receberam: quem.size, responderam: (quem & respondeu).size, compraram: da_versao.pluck(:contato).uniq.size,
        valor: (CampaignJourney::ComprasNaJanela.valor(da_versao) if com_valor) }
    end
  end

  private

  # { contact_id => versão } de quem do teste recebeu.
  def recebeu
    @recebeu ||= begin
      enviados = CampaignJourney::ComprasDaCampanha.recipients_de(@campaign).where.not(sent_at: nil)
      enviados = enviados.where.not(id: texto_da_conversa_aberta) if @campaign.is_a?(Campaign)
      do_teste.where(contact_id: enviados.select(:contact_id)).pluck(:contact_id, :versao).to_h
    end
  end

  def texto_da_conversa_aberta
    CampaignFreeTextDelivery.where(campaign_id: @campaign.id).select(:campaign_recipient_id)
  end

  def do_teste
    CampaignVersionContact.where(campaign_audience_link_id: @link.id, fase: 'teste')
  end

  def respondeu
    @respondeu ||= CampaignJourney::ResultReplies.new(@account, CampaignJourney::CampaignMarks.source_id_for(@campaign)).contact_ids.to_set
  end

  def compras_por_versao(pipeline_ids)
    return [] unless Crm::Config.enabled?

    CampaignJourney::ComprasDaCampanha.new(@account, @campaign, CampaignJourney::CampaignMarks.source_id_for(@campaign))
                                      .compras_por_pessoa(pipeline_ids: pipeline_ids)
  end
end
