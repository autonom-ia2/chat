# O mesmo clique num anúncio de clique para o Messenger ou o Direct (#2607). Quando a pessoa já tinha conversa, a Meta
# manda o clique duas vezes: no evento só de referral e, segundos depois, na primeira mensagem, cada um com o seu id
# (visto em produção, apesar da doc). Vale um toque só, e fica o primeiro (o do evento).
#
# A hora que compara é a do clique que a Meta manda (`timestamp` do evento ou da mensagem), levada dentro do referral
# em `clicked_at` (Crm::MetaAds::MessagingReferral.with_click_time) e gravada no `touched_at` do toque: fila atrasada ou
# nova tentativa não separam o mesmo clique, e dois cliques guardados em horas diferentes não se juntam.
module Crm::MetaAds::MessagingReferral::Click
  WINDOW = 1.minute
  # O `timestamp` da Meta vem em milissegundos na mensagem e em segundos no evento só de referral: acima disto é ms.
  MILLISECONDS_FROM = 10**11

  module_function

  # O `timestamp` da Meta (segundos ou milissegundos, número ou texto) como hora; nil quando não veio ou não é número.
  def time(timestamp)
    value = timestamp.to_s.strip
    return if value.empty? || !value.delete('0-9').empty?

    number = value.to_i
    return if number.zero?

    Time.zone.at(number >= MILLISECONDS_FROM ? number / 1000.0 : number)
  end

  # Ctwa::CampaignBuilder pergunta, dentro da trava da conversa, se o toque novo repete um já gravado. Só o clique para o
  # Messenger ou o Direct: os outros toques seguem o ctwa_clid ou o source_id. Toque sem a hora da Meta vale agora.
  def same?(existing, touch)
    return false unless Ctwa::CampaignBuilder::MESSAGING_AD_SOURCES.include?(touch['source'])
    return false unless existing['source'] == touch['source'] && existing['source_id'] == touch['source_id']

    before = Time.zone.parse(existing['touched_at'].to_s)
    now = Time.zone.parse(touch['touched_at'].to_s) || Time.current
    before.present? && (now - before).abs <= WINDOW
  end
end
