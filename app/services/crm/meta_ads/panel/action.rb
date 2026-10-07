# As peças de regra da F3 (#1088, CA-3.3) que o consultor da F5 (#1110) reaproveita. A ação do dia em si saiu
# daqui: quem escolhe e ordena as ações agora é `Crm::MetaAds::Advisor::Decision`. Ficaram as contas que ela, os
# fatos, a lista do caminho e a sugestão de mensagem usam, para que o painel e o consultor não discordem:
#
# - `stalled`: propostas de anúncio paradas há mais de STALLED_AFTER;
# - `top_ad_name`: o anúncio de onde veio a maior parte delas;
# - `tracking_payload`: menos de MIN_CONFIDENT das conversas de anúncio têm o anúncio identificado;
# - `wait_payload`: quantas conversas faltam para o primeiro veredito.
module Crm::MetaAds::Panel::Action
  STALLED_AFTER = 3.days
  MIN_CONFIDENT = 0.7
  MIN_SAMPLE = 5
  STALLED_LIST = 10

  module_function

  def stalled(cards, now)
    cards.select { |card| card.status == 'open' && card.quote? && card.waiting_since && card.waiting_since < now - STALLED_AFTER }
         .sort_by(&:waiting_since)
  end

  # O anúncio de onde veio a maior parte das propostas paradas.
  def top_ad_name(stalled, ads)
    top_ad = stalled.filter_map(&:ad_id).tally.max_by { |_id, count| count }&.first
    ads.find { |ad| ad[:ad_id] == top_ad }&.dig(:name)
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
