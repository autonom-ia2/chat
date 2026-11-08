# O caminho do dinheiro clicável (#1110, F5, D5.7): a lista por trás de cada número do caminho do painel.
#
# A coorte é a mesma do Panel::Report do período, então o total bate com o número que a pessoa clicou:
# - `conversations`: cada conversa de anúncio, com o card principal dela, a mais recente primeiro;
# - `quotes`: as propostas, as abertas paradas há mais tempo no topo, depois as ganhas;
# - `sales`: as vendas, da maior para a menor; para quem não vê os valores de venda (#2075), da mais recente para a
#   mais antiga, para a ordem não dizer quem comprou mais;
# - `slow_replies`: as conversas sem resposta (a entrada mais antiga primeiro) e as respondidas depois de
#   SLOW_SECONDS (a mais lenta primeiro), pelo Panel::ResponseTime do mesmo período.
#
# Cada linha leva à conversa e ao card no CRM. No máximo LIST_LIMIT linhas; `total` é a lista inteira. Título do
# card ou, sem card, o nome do contato. Com `visible` (Crm::MetaAds::VisibleConversations, #1794), só as conversas
# que a pessoa já veria na lista de conversas; o total conta essas. O valor de cada card segue a mesma pessoa
# (Panel::SalesValue): sem `sales_value_view`, nil com `value_hidden`, menos o card de que ela é dona.
#
# Sem conexão (Anúncios sem login, #1960), `scope[:account]` diz a conta; `scope[:ad_id]` limita as conversas às de
# um anúncio (as pessoas do anúncio por dentro); `scope[:report]` reaproveita o Report já montado (mesma coorte);
# `scope[:limit]` troca o LIST_LIMIT (o relatório baixado leva a lista inteira).
class Crm::MetaAds::Panel::PathList
  STEPS = %w[conversations quotes sales slow_replies].freeze
  LIST_LIMIT = 50
  SLOW_SECONDS = 300

  def initialize(connection, step:, period: nil, visible: nil, **scope)
    raise ArgumentError, "unknown step #{step}" unless STEPS.include?(step)

    @step = step
    @visible = visible
    @ad_id = scope[:ad_id]&.to_s
    @limit = scope[:limit] || LIST_LIMIT
    @report = scope[:report] || Crm::MetaAds::Panel::Report.new(connection, period: period, account: scope[:account])
  end

  def payload
    rows = only_visible(send(:"#{@step}_rows"))
    shown = rows.first(@limit)
    names = contact_names(shown.reject { |_id, card| card&.title.present? }.map(&:first))
    { step: @step, period: @report.period.key, days: @report.days, total: rows.size, items: shown.map { |id, card| item(id, card, names) } }
  end

  private

  # Cada *_rows devolve [[conversation_id, card ou nil], ...] na ordem da lista.
  def conversations_rows
    touches = @ad_id ? cohort.touches.select { |_id, (ad, _at)| ad == @ad_id } : cohort.touches
    touches.sort_by { |_id, (_ad, at)| at }.reverse.map { |id, _touch| [id, main_card(id)] }
  end

  def quotes_rows
    cohort.cards.select(&:quote?).sort_by { |card| [card.sale? ? 1 : 0, card.waiting_since || Time.current] }
          .map { |card| [card.conversation_id, card] }
  end

  def sales_rows
    sales = cohort.cards.select(&:sale?)
    sorted = if Crm::MetaAds::Panel::SalesValue.visible?(@visible)
               sales.sort_by { |card| -card.value }
             else
               sales.sort_by { |card| -card.closed_at.to_i }
             end
    sorted.map { |card| [card.conversation_id, card] }
  end

  def slow_replies_rows
    unanswered = responses.select { |_id, reply| reply[:answered] == false }.keys
    late = responses.select { |_id, reply| reply[:answered] && reply[:seconds].to_i > SLOW_SECONDS }.keys
    (unanswered.sort_by { |id| touched_at(id) } + late.sort_by { |id| -responses[id][:seconds] }).map { |id| [id, main_card(id)] }
  end

  def cohort
    @report.cohort
  end

  def only_visible(rows)
    return rows if @visible.nil?

    ids = @visible.ids(rows.map(&:first))
    rows.select { |row| ids.include?(row.first) }
  end

  def item(conversation_id, card, names)
    reply = responses_needed? ? responses[conversation_id] : nil
    row = {
      conversation_id: conversation_id, card_id: card&.id, title: card&.title.presence || names[conversation_id],
      ad_name: ad_names[cohort.conversation_ads[conversation_id]], touched_at: touched_at(conversation_id),
      stage_name: card&.stage_name, status: card&.status, value: card&.value, waiting_since: card&.waiting_since,
      stalled: card ? stalled_ids.include?(card.id) : false, response_seconds: reply&.dig(:seconds), answered: reply&.dig(:answered)
    }
    with_value(row, card)
  end

  def with_value(row, card)
    card.nil? || Crm::MetaAds::Panel::SalesValue.card?(@visible, card) ? row : row.merge(value: nil, value_hidden: true)
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
    @primary_ids ||= Crm::Card.where(account_id: @report.account_id, conversation_id: cohort.touches.keys).pluck(:id).to_set
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

    Conversation.where(account_id: @report.account_id, id: conversation_ids).joins(:contact).pluck(:id, 'contacts.name').to_h
  end

  # O tempo de resposta só entra nas listas de conversa; proposta e venda mostram a espera do card.
  def responses_needed?
    %w[conversations slow_replies].include?(@step)
  end

  # { conversation_id => { seconds:, answered: } }
  def responses
    @responses ||= Crm::MetaAds::Panel::ResponseTime.new(account_id: @report.account_id, range: @report.range, starts: response_starts)
                                                    .by_conversation
  end

  # Dentro de um anúncio, o tempo de resposta só das conversas dele (a coorte é da conta toda).
  def response_starts
    starts = cohort.starts
    return starts if starts.nil? || @ad_id.nil?

    starts.slice(*cohort.touches.select { |_id, (ad, _at)| ad == @ad_id }.keys)
  end
end
