# Anúncios da Meta, F4a (#1100): a IA no painel. Só administrador (policy Crm::MetaAdsConnection :show?).
#
# POST daily_action  {days}    → "O que fazer hoje" escrito pela IA a partir dos números do painel. Sem IA ou
#                                com resultado guardado do dia, 200 na hora; senão 202 com poll_url.
# POST quote_message {card_id} → mensagem sugerida para retomar uma proposta parada. O card precisa estar entre as
#                                paradas recalculadas aqui; janela fechada ou IA indisponível, 200 na hora; senão 202.
#
# Nada é enviado daqui: a mensagem sugerida só sai pelo clique "Enviar na conversa" da tela.
class Api::V1::Accounts::Crm::MetaAdsAiController < Api::V1::Accounts::Crm::BaseController
  include DeferInteractiveAi

  before_action :ensure_administrator

  def daily_action
    connection = current_connection
    return render json: { daily_action: nil } if connection.blank? || connection.ad_account_id.blank?

    report = ::Crm::MetaAds::Panel::Report.new(connection, days: params[:days])
    payload = report.payload
    immediate = immediate_daily_action(connection, report, payload)
    return render json: { daily_action: immediate } if immediate

    defer_interactive_ai('meta_ads_daily_action', { days: report.days, language: I18n.locale.to_s })
  end

  def quote_message
    card = Current.account.crm_cards.find_by(id: params[:card_id])
    return render_unprocessable('card_not_found') if card.blank?

    row = ::Crm::MetaAds::QuoteMessageSuggester.stalled_card(current_connection, card.id)
    return render_unprocessable('card_not_stalled') if row.blank?

    conversation = Current.account.conversations.find_by(id: row.conversation_id)
    return render json: { error: 'forbidden' }, status: :forbidden unless conversation_visible?(conversation)

    respond_quote_message(card, conversation)
  end

  private

  # Janela fechada ou IA indisponível: responde na hora, sem a IA.
  def respond_quote_message(card, conversation)
    suggester = ::Crm::MetaAds::QuoteMessageSuggester.new(card: card, conversation: conversation, language: I18n.locale.to_s)
    reason = suggester.unavailable_reason
    return render json: { quote_message: suggester.result(applies: false, reason: reason) } if reason

    defer_interactive_ai('meta_ads_quote_message', { card_id: card.id, language: I18n.locale.to_s })
  end

  # A resposta que não precisa da IA: sem IA, nada no período, já guardada, ou o teto do dia.
  def immediate_daily_action(connection, report, payload)
    ai_action = ::Crm::MetaAds::Panel::AiAction
    reason = ai_action.unavailable_reason(Current.account)
    return ai_action.rule(payload, reason) if reason
    return ai_action.rule(payload, 'not_applicable') if payload[:action][:kind] == 'no_data'

    cache = ::Crm::MetaAds::Panel::AiActionCache.new(connection: connection, report: payload, zone: report.zone, locale: I18n.locale)
    cached = cache.read
    return cached if cached
    return cache.last || ai_action.rule(payload, 'daily_limit') unless cache.reserve!

    nil
  end

  def conversation_visible?(conversation)
    return false if conversation.blank?

    Pundit.policy!(pundit_user, conversation).show? &&
      ::Crm::Conversations::Visibility.new(account: Current.account, user: Current.user, account_user: Current.account_user)
                                      .visible?(conversation)
  end

  def ensure_administrator
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).show?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end
end
