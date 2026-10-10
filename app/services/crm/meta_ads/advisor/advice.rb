# O `Advice` da API (#1110, F5, §4.2): o que a tela e o resumo recebem de um run do consultor. Só a Analysis o
# monta (`current`, `serialize`, `daily`).
#
# - Os textos guardados têm marcadores; cada leitura põe os valores atuais (Format.render). Marcador sem valor
#   atual → aquela ação volta ao texto da regra (`source: 'rule'`): nunca sai texto com buraco.
# - `writer.status` diz o que a tela deve fazer: `pending` só quando o run pode ser reivindicado agora; `pending`
#   esperando a nova tentativa sai como `rule`/`ai_error`; `writing` abandonado sai como `pending`.
# - Dispensada não vem. O título dos cards das propostas paradas só entra aqui, lido na hora, por id (os fatos
#   nunca guardam título).
# - O botão do Gerenciador da Meta é montado aqui, com a conta sem o prefixo `act_` e o id do anúncio.
class Crm::MetaAds::Advisor::Advice
  BUTTONS = {
    'stalled_quotes' => 'stalled_list', 'slow_response' => 'slow_replies', 'fix_tracking' => 'connection_step',
    'review_ad' => 'ad_detail', 'refresh_creative' => 'ad_detail', 'scale_ad' => 'ads_manager', 'auction_pressure' => 'acknowledge'
  }.freeze
  CONNECTION_STEP = 3
  ADS_MANAGER_URL = 'https://adsmanager.facebook.com/adsmanager/manage/ads'.freeze
  VISIBLE = %w[open accepted].freeze
  NO_TEXT = { source: 'rule', headline: nil, body: nil, why: nil }.freeze

  # actions: as da Decision (atuais) ou as guardadas no run; today: History.today (id, status, opened_at).
  def initialize(run, actions, today:, locale:)
    @run = run
    @actions = actions
    @today = today
    @locale = locale
  end

  def payload
    visible = @actions.select { |action| row(action).nil? || VISIBLE.include?(row(action)[:status].to_s) }
    { run_id: @run.id, local_date: @run.local_date.iso8601, rules_version: @run.rules_version, writer: writer,
      actions: visible.each_with_index.map { |action, index| action_payload(action, index + 1) } }
  end

  private

  def writer
    case @run.writer_status
    when 'pending' then @run.retry_after&.future? ? { status: 'rule', reason: 'ai_error' } : { status: 'pending', reason: @run.writer_reason }
    when 'writing' then { status: abandoned? ? 'pending' : 'writing', reason: nil }
    else { status: @run.writer_status, reason: @run.writer_reason }
    end
  end

  def abandoned?
    @run.writing_started_at < Time.current - Crm::MetaAds::Advisor::Analysis::STALE_WRITING
  end

  def row(action)
    @today[[action[:kind], action[:subject_key]]]
  end

  def action_payload(action, position)
    facts = action[:facts].to_h.deep_stringify_keys
    {
      position: position, kind: action[:kind], variant: action[:variant], ad_id: action[:ad_id], ad_name: facts['ad_name'],
      facts: facts.except('cards'), button: button(action), cards: action[:kind] == 'stalled_quotes' ? cards(facts['cards']) : []
    }.merge(gesture(action), text(action, facts))
  end

  # O que a pessoa já fez com a ação (fillers não têm linha: id nil).
  def gesture(action)
    stored = row(action) || {}
    { id: stored[:id], status: stored[:status] || action[:status] || action[:status_at_creation], opened: stored[:opened_at].present? }
  end

  # Os três textos da IA renderizados com os fatos atuais, ou a regra se algum não fecha.
  def text(action, facts)
    stored = @run.texts.to_h["#{action[:kind]}|#{action[:subject_key]}"]
    return NO_TEXT if stored.blank?

    keys = Crm::MetaAds::Advisor::Writer::TEXT_KEYS
    rendered = keys.to_h do |key|
      [key.to_sym, Crm::MetaAds::Advisor::Format.render(stored[key], facts.except('cards'), locale: @locale, currency: @run.facts['currency'])]
    end
    rendered.value?(nil) ? NO_TEXT : rendered.merge(source: 'ai')
  end

  def button(action)
    target = BUTTONS.fetch(action[:kind], 'none')
    url = if target == 'ads_manager'
            "#{ADS_MANAGER_URL}?#{{ act: @run.ad_account_id.delete_prefix('act_'), selected_ad_ids: action[:ad_id] }.to_query}"
          end
    { target: target, step: (CONNECTION_STEP if target == 'connection_step'), url: url }
  end

  def cards(list)
    list = Array(list)
    titles = Crm::Card.where(account_id: @run.account_id, id: list.pluck('id')).pluck(:id, :title).to_h
    list.map do |card|
      { id: card['id'], title: titles[card['id']], value: card['value'], conversation_id: card['conversation_id'],
        waiting_since: card['waiting_since'] }
    end
  end
end
