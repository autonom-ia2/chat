# Quanto custa a campanha com a conversa aberta (#1335): quantas pessoas do Público falaram com a caixa nas últimas
# 24 horas (recebem a mensagem escrita) e quantas não (recebem o modelo), o preço do modelo pela categoria, o da
# mensagem escrita (tarifa de serviço) e as grátis do mês deste número (contrato do #1322: `Whatsapp::Pricing` e
# `Whatsapp::ServiceMessageCount`). Não depende da tela de Modelos: vale para toda conta com a flag.
#
# É uma foto: no envio a janela é conferida de novo, pessoa por pessoa (CampaignJourney::ConversaAberta::Envio).
class CampaignJourney::ConversaAberta::Contagem
  SERVICE = 'service'.freeze

  def initialize(account:, campaign_import:, inbox:, categoria: nil, now: Time.current)
    @account = account
    @campaign_import = campaign_import
    @inbox = inbox
    @categoria = categoria
    @now = now
  end

  def perform
    ids = contact_ids
    window = Whatsapp::ServiceWindow.new(inbox: @inbox, now: @now)
    dentro = window.open_contact_ids(ids)
    { dentro: dentro.size, fora: ids.size - dentro.size, fecham_logo: window.closing_soon_count(dentro.to_a),
      conferido_em: @now.iso8601, precos: precos, franquia: franquia,
      campos: CampaignJourney::ConversaAberta::Texto.campos(@campaign_import.extra_columns) }
  end

  private

  # Quem pode receber WhatsApp pelo Público (a mesma regra do envio), sem quem pediu para parar.
  def contact_ids
    ids = CampaignJourney::AudienceContacts.whatsapp_contact_ids(@campaign_import, account: @account)
    @account.contacts.where(id: ids).not_opted_out.pluck(:id)
  end

  def precos
    { modelo: preco(@categoria.presence && Whatsapp::Pricing.per_message(@categoria)),
      escrita: preco(Whatsapp::Pricing.per_message(SERVICE)) }
  end

  def preco(price)
    price && { valor: price.amount.to_s('F'), moeda: price.currency }
  end

  def franquia
    tier = Whatsapp::Pricing.free_tier(SERVICE)
    return unless tier

    usadas = Whatsapp::ServiceMessageCount.new(account: @account, inbox_ids: [@inbox.id], now: @now).perform[@inbox.id]
    { limite: tier[:messages], usadas: usadas }
  end
end
