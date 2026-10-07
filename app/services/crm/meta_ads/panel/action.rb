# A ação do dia, por regra (#1088, F3a, CA-3.3). A versão escrita pela IA é da F4; aqui a ordem é fixa e cada
# ação traz os números do porquê:
#
# 1. `stalled_quotes`: propostas de anúncio paradas há mais de STALLED_AFTER — retomar custa menos que anunciar;
# 2. `fix_tracking`: menos de MIN_CONFIDENT das conversas de anúncio têm o anúncio identificado — sem isso o
#    custo por venda não fecha;
# 3. `wait`: nada a corrigir; mostra quantas conversas faltam para o primeiro veredito;
# 4. `on_track`: nada parado e os anúncios já têm veredito — a ação é olhar o veredito de cada um;
# 5. `no_data`: nenhum anúncio gastou nem trouxe conversa no período.
module Crm::MetaAds::Panel::Action
  STALLED_AFTER = 3.days
  MIN_CONFIDENT = 0.7
  MIN_SAMPLE = 5
  STALLED_LIST = 10

  module_function

  def for(cards:, confidence:, ads:, now: Time.current)
    stalled = stalled(cards, now)
    return stalled_payload(stalled, ads) if stalled.any?

    tracking = tracking_payload(confidence)
    return tracking if tracking

    wait_payload(ads)
  end

  def stalled(cards, now)
    cards.select { |card| card.status == 'open' && card.quote? && card.waiting_since && card.waiting_since < now - STALLED_AFTER }
         .sort_by(&:waiting_since)
  end

  def stalled_payload(stalled, ads)
    {
      kind: 'stalled_quotes', count: stalled.size, value: stalled.sum(&:value), days: STALLED_AFTER.in_days.to_i,
      ad_name: top_ad_name(stalled, ads), cards: stalled.first(STALLED_LIST).map { |card| card_payload(card) }
    }
  end

  # O anúncio de onde veio a maior parte das propostas paradas.
  def top_ad_name(stalled, ads)
    top_ad = stalled.filter_map(&:ad_id).tally.max_by { |_id, count| count }&.first
    ads.find { |ad| ad[:ad_id] == top_ad }&.dig(:name)
  end

  def card_payload(card)
    { id: card.id, title: card.title, value: card.value, conversation_id: card.conversation_id, waiting_since: card.waiting_since }
  end

  def tracking_payload(confidence)
    total = confidence[:conversations].to_i
    known = confidence[:ad].to_i + confidence[:ad_name].to_i
    return if total < MIN_SAMPLE || known >= total * MIN_CONFIDENT

    { kind: 'fix_tracking', conversations: total, unknown: total - known }
  end

  def wait_payload(ads)
    best = ads.max_by { |ad| ad[:conversations] }
    return { kind: 'no_data' } if best.nil?

    missing = Crm::MetaAds::Panel::Verdict::MIN_CONVERSATIONS - best[:conversations]
    return { kind: 'on_track' } unless missing.positive?

    { kind: 'wait', ad_name: best[:name], missing_conversations: missing }
  end
end
