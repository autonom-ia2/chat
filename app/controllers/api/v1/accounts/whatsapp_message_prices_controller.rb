# Preço por mensagem do WhatsApp oficial e a franquia do mês (#1332, épico #1320). A tabela vem de
# `Whatsapp::Pricing` (GlobalConfig WHATSAPP_MESSAGE_PRICES); a contagem do mês, de `Whatsapp::ServiceMessageCount`.
#
#   GET /api/v1/accounts/:account_id/whatsapp_message_prices
#   => { payload: { country, currency, effective_from, prices: { marketing, utility, authentication, service },
#                   free_tier: { service: { messages, period, per } } | {},
#                   service_usage: [{ inbox_id, name, messages }] } }
#
# Valores em texto ("0.3217") para não perder casas. Categoria sem preço vem null. Ver: whatsapp_templates_view ou
# campaign_view.
class Api::V1::Accounts::WhatsappMessagePricesController < Api::V1::Accounts::BaseController
  COUNTRY = Whatsapp::Pricing::DEFAULT_COUNTRY

  before_action :check_authorization

  def index
    prices = Whatsapp::Pricing::CATEGORIES.index_with { |category| Whatsapp::Pricing.per_message(category, country: COUNTRY) }
    any = prices.values.compact.first
    tier = Whatsapp::Pricing.free_tier('service', country: COUNTRY)
    render json: { payload: {
      country: COUNTRY, currency: any&.currency, effective_from: any&.effective_from,
      prices: prices.transform_values { |price| price&.amount&.to_s('F') },
      free_tier: tier ? { service: tier } : {},
      service_usage: tier ? service_usage : []
    } }
  end

  private

  def check_authorization
    authorize(:whatsapp_message_price, :index?)
  end

  def service_usage
    inboxes = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id)
                     .select { |inbox| Whatsapp::Templates::MetaClient.supported?(inbox) }
    counts = Whatsapp::ServiceMessageCount.new(account: Current.account, inbox_ids: inboxes.map(&:id)).perform
    inboxes.map { |inbox| { inbox_id: inbox.id, name: inbox.name, messages: counts[inbox.id] } }
  end
end
