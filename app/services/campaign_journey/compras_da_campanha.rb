# #3098 (F2 do épico #3095): "Quem recebeu e comprou" no resultado da campanha com público.
#
# Quem recebeu = quem tem envio desta campanha (sent_at). Comprou = card fechado como venda pela mesma régua do
# ResultReplies (ganho, arquivado depois de ganho, renovação resolvida com apólice nova; valor = prêmio da apólice nova
# ou o valor do card), ligado à pessoa pelo contact_id do card, com closed_at entre o envio e o envio + a janela da
# campanha (`janela_de_compra_dias` do link). Decisão do Rodrigo: a compra conta só na campanha mais recente antes
# dela — se a pessoa recebeu outra campanha entre este envio e a compra, a compra é da outra.
#
# Separa quem respondeu (a conversa ganhou a marca da campanha, ResultReplies) de quem comprou sem responder. Com grupo
# de controle, conta quem do grupo comprou na mesma janela, a partir do primeiro envio da campanha (o momento em que
# ele "teria recebido"), com a mesma regra da campanha mais recente.
#
# O valor só vai para quem vê valor de venda (Crm::ValorDeVenda); as contagens ficam. Funis que a pessoa não vê nos
# relatórios (#1148) ficam de fora, como no resto do resultado. nil quando a campanha não tem público (sem link).
class CampaignJourney::ComprasDaCampanha
  # Os destinatários da campanha, no lugar onde cada canal os guarda.
  def self.recipients_de(campaign)
    case campaign
    when EmailCampaign then EmailCampaignRecipient.where(email_campaign_id: campaign.id)
    when WhatsappApiCampaign then WhatsappApiCampaignRecipient.where(whatsapp_api_campaign_id: campaign.id)
    else CampaignRecipient.where(campaign_id: campaign.id)
    end
  end

  def initialize(account, campaign, source_id)
    @account = account
    @campaign = campaign
    @source_id = source_id
    @link = CampaignAudienceLink.for_campaign(campaign)
  end

  def payload(user:, account_user:)
    return if @link.nil?

    @com_valor = Crm::ValorDeVenda.ve?(account_user)
    visible = Crm::Access::VisiblePipelines.new(user: user, account: @account, account_user: account_user)
    @pipeline_ids = visible.report_ids if visible.restricted?
    montar
  end

  # #3099: as compras de cada pessoa que recebeu, pela mesma régua (janela, campanha mais recente), para comparar as
  # duas versões da mensagem. `pipeline_ids`: nil = todos os funis (a escolha automática da vencedora); senão os funis
  # que quem lê vê nos relatórios. [{ contato:, inicio:, fechado_em:, moeda:, centavos: }]
  def compras_por_pessoa(pipeline_ids: nil)
    return [] if @link.nil?

    @pipeline_ids = pipeline_ids
    sem_campanha_depois(compras_de(envios))
  end

  private

  def montar
    compras = sem_campanha_depois(compras_de(envios))
    responderam = CampaignJourney::ResultReplies.new(@account, @source_id).contact_ids.to_set
    {
      janela_dias: janela,
      contando_ate: contando_ate,
      receberam: envios.size,
      compraram: resumo(compras),
      responderam: resumo(compras.select { |compra| responderam.include?(compra[:contato]) }),
      sem_responder: resumo(compras.reject { |compra| responderam.include?(compra[:contato]) }),
      controle: controle
    }
  end

  def janela
    @link.janela_de_compra_dias
  end

  # { contact_id => primeiro envio desta campanha para a pessoa }
  def envios
    @envios ||= recipients_desta.where.not(sent_at: nil).where.not(contact_id: nil).group(:contact_id).minimum(:sent_at)
  end

  def recipients_desta
    self.class.recipients_de(@campaign)
  end

  # A janela ainda aberta para alguém: até quando os números podem subir (epoch), ou nil quando já fechou.
  def contando_ate
    ultimo = envios.values.max
    return if ultimo.nil?

    ate = ultimo + janela.days
    ate.to_i if ate.future?
  end

  def compras_de(inicios)
    CampaignJourney::ComprasNaJanela.new(@account, dias: janela, pipeline_ids: @pipeline_ids).de(inicios)
  end

  # Tira a compra que pertence a outra campanha: a pessoa recebeu outra campanha entre este início e a compra.
  def sem_campanha_depois(compras)
    return compras if compras.empty?

    outros = outros_envios(compras.pluck(:contato).uniq, compras.pluck(:inicio).min)
    compras.reject do |compra|
      outros[compra[:contato]].to_a.any? { |enviado_em| enviado_em > compra[:inicio] && enviado_em <= compra[:fechado_em] }
    end
  end

  # { contact_id => [sent_at] } dos envios de outras campanhas da conta (qualquer canal) desde `desde`.
  def outros_envios(contatos, desde)
    envios_da_conta.flat_map { |fonte| fonte.where(contact_id: contatos).where(sent_at: desde..).pluck(:contact_id, :sent_at) }
                   .group_by(&:first).transform_values { |linhas| linhas.map(&:last) }
  end

  # Os destinatários de todas as campanhas da conta, menos os desta.
  def envios_da_conta
    [
      CampaignRecipient.where(account_id: @account.id).where.not(campaign_id: id_se(Campaign)),
      WhatsappApiCampaignRecipient.where(account_id: @account.id).where.not(whatsapp_api_campaign_id: id_se(WhatsappApiCampaign)),
      EmailCampaignRecipient.joins(:email_campaign).where(email_campaigns: { account_id: @account.id })
                            .where.not(email_campaign_id: id_se(EmailCampaign))
    ]
  end

  def id_se(classe)
    @campaign.id if @campaign.is_a?(classe)
  end

  # { pessoas, valor: [{ currency, cents }] | nil }: pessoas distintas; o valor por moeda, maior primeiro.
  def resumo(compras)
    { pessoas: compras.pluck(:contato).uniq.size, valor: (CampaignJourney::ComprasNaJanela.valor(compras) if @com_valor) }
  end

  # { pessoas, compraram } do grupo de controle, a partir do primeiro envio da campanha. nil sem grupo ou sem envio.
  def controle
    grupo = CampaignJourney::GrupoDeControle.new(@link)
    return unless grupo.ativo?

    inicio = envios.values.min
    ids = grupo.ids.to_a
    return if inicio.nil? || ids.empty?

    compras = sem_campanha_depois(compras_de(ids.index_with { inicio }))
    { pessoas: ids.size, compraram: compras.pluck(:contato).uniq.size }
  end
end
