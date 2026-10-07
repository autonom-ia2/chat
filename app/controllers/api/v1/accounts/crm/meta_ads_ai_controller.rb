# Anúncios da Meta, F4a (#1100): a IA no painel. Só administrador (policy Crm::MetaAdsConnection :show?).
#
# POST daily_action  {days}    → o texto do consultor (F5, #1110) pela IA: o `Advice` do dia. `days` é aceito e
#                                ignorado (D5.2: o consultor não depende do período da tela). Já escrito, pela
#                                regra ou com outra aba escrevendo, 200 na hora; IA indisponível, só fillers ou
#                                teto do dia, o run fecha pela regra e 200; senão 202 com poll_url. O teto só é
#                                reservado na escrita (Advisor::Analysis.write!), nunca aqui.
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

    advice = advisor.current(connection, locale: I18n.locale.to_s)
    immediate = immediate_daily_action(advice)
    return render json: { daily_action: immediate } if immediate

    defer_interactive_ai('meta_ads_daily_action', { run_id: advice[:run_id], language: I18n.locale.to_s })
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

  # O Advice que não precisa da IA: já escrito, pela regra, ou outra aba escrevendo (a tela confere o painel de
  # novo). Livre mas sem IA, só com fillers ou sem vaga no teto: fecha pela regra com o motivo. nil = pedir à IA.
  def immediate_daily_action(advice)
    return advice unless advice.dig(:writer, :status) == 'pending'

    run = ::Crm::MetaAdvisorRun.find_by!(id: advice[:run_id], account_id: Current.account.id)
    reason = advisor.immediate_reason(run)
    return if reason.nil?

    advisor.rule!(run, reason)
    advisor.serialize(run.reload, I18n.locale.to_s)
  end

  def advisor
    ::Crm::MetaAds::Advisor::Analysis
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
