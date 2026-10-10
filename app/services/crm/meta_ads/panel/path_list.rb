# O caminho do dinheiro clicável (#1110, F5, D5.7): a lista por trás de cada número do caminho do painel.
#
# A coorte é a mesma do Panel::Report do período, então o total bate com o número que a pessoa clicou:
# - `conversations`: cada conversa de anúncio, com o card principal dela, a mais recente primeiro;
# - `quotes`: as propostas, as abertas paradas há mais tempo no topo, depois as ganhas;
# - `sales`: as vendas, da maior para a menor;
# - `slow_replies`: as conversas sem resposta (a entrada mais antiga primeiro) e as respondidas depois de
#   SLOW_SECONDS (a mais lenta primeiro), pelo Panel::ResponseTime do mesmo período.
#
# Cada linha leva à conversa e ao card no CRM. No máximo LIST_LIMIT linhas; `total` é a lista inteira. Título do
# card ou, sem card, o nome do contato: a policy do painel é de administrador, que já vê os dois.
class Crm::MetaAds::Panel::PathList
  STEPS = %w[conversations quotes sales slow_replies].freeze
  LIST_LIMIT = 50
  SLOW_SECONDS = 300

  def initialize(connection, step:, days:)
    raise ArgumentError, "unknown step #{step}" unless STEPS.include?(step)

    @connection = connection
    @step = step
    @report = Crm::MetaAds::Panel::Report.new(connection, days: days)
  end

  def payload
    rows = send(:"#{@step}_rows")
    shown = rows.first(LIST_LIMIT)
    names = contact_names(shown.reject { |_id, card| card&.title.present? }.map(&:first))
    { step: @step, days: @report.days, total: rows.size, items: shown.map { |id, card| item(id, card, names) } }
  end

  private

  # Cada *_rows devolve [[conversation_id, card ou nil], ...] na ordem da lista.
  def conversations_rows
    cohort.touches.sort_by { |_id, (_ad, at)| at }.reverse.map { |id, _touch| [id, main_card(id)] }
  end

  def quotes_rows
    cohort.cards.select(&:quote?).sort_by { |card| [card.sale? ? 1 : 0, card.waiting_since || Time.current] }
          .map { |card| [card.conversation_id, card] }
  end

  def sales_rows
    cohort.cards.select(&:sale?).sort_by { |card| -card.value }.map { |card| [card.conversation_id, card] }
  end

  def slow_replies_rows
    unanswered = responses.select { |_id, reply| reply[:answered] == false }.keys
    late = responses.select { |_id, reply| reply[:answered] && reply[:seconds].to_i > SLOW_SECONDS }.keys
    (unanswered.sort_by { |id| touched_at(id) } + late.sort_by { |id| -responses[id][:seconds] }).map { |id| [id, main_card(id)] }
  end

  def cohort
    @report.cohort
  end

  def item(conversation_id, card, names)
    reply = responses_needed? ? responses[conversation_id] : nil
    {
      conversation_id: conversation_id, card_id: card&.id, title: card&.title.presence || names[conversation_id],
      ad_name: ad_names[cohort.conversation_ads[conversation_id]], touched_at: touched_at(conversation_id),
      stage_name: card&.stage_name, status: card&.status, value: card&.value, waiting_since: card&.waiting_since,
      stalled: card ? stalled_ids.include?(card.id) : false, response_seconds: reply&.dig(:seconds), answered: reply&.dig(:answered)
    }
  end

  def touched_at(conversation_id)
    cohort.touches.dig(conversation_id, 1)
  end

  # O card cuja conversa principal é esta; sem ele, o primeiro card ligado a ela.
  def main_card(conversation_id)
    cards = cards_by_conversation[conversation_id]
    return if cards.blank?

    cards.find { |card| primary_ids.include?(card.id) } || cards.min_by(&:id)
  end

  def cards_by_conversation
    @cards_by_conversation ||= cohort.cards.group_by(&:conversation_id)
  end

  def primary_ids
    @primary_ids ||= Crm::Card.where(account_id: @connection.account_id, conversation_id: cohort.touches.keys).pluck(:id).to_set
  end

  def stalled_ids
    @stalled_ids ||= Crm::MetaAds::Panel::Action.stalled(cohort.cards, Time.current).to_set(&:id)
  end

  def ad_names
    @ad_names ||= @report.ads.to_h { |ad| [ad[:ad_id], ad[:name]] }
  end

  # Só das linhas mostradas e sem título de card.
  def contact_names(conversation_ids)
    return {} if conversation_ids.empty?

    Conversation.where(account_id: @connection.account_id, id: conversation_ids).joins(:contact).pluck(:id, 'contacts.name').to_h
  end

  # O tempo de resposta só entra nas listas de conversa; proposta e venda mostram a espera do card.
  def responses_needed?
    %w[conversations slow_replies].include?(@step)
  end

  # { conversation_id => { seconds:, answered: } }
  def responses
    @responses ||= Crm::MetaAds::Panel::ResponseTime.new(account_id: @connection.account_id, range: @report.range).by_conversation
  end
end
