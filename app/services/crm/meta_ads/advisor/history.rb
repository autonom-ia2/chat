# O que a pessoa já fez com as ações do consultor (#1110, F5, §1.3 e §1.4), lido a cada análise e nunca guardado
# no cache dos fatos: depois de um aceite, a próxima leitura já precisa saber.
#
# - `for`: os anúncios com aumento de orçamento aceito nos últimos SCALE_COOLDOWN_DAYS dias, hoje incluído
#   (aceito em 04/10 → só escala de novo em 07/10). É o "descanso" da regra `scale`.
# - `today`: as ações já gravadas hoje, com o status (aceita fica, dispensada sai) e os fatos guardados, que a
#   Decision usa quando a regra já não dispara.
module Crm::MetaAds::Advisor::History
  module_function

  def for(account_id, local_date)
    cooldown = Crm::MetaAds::Advisor::Rules::SCALE_COOLDOWN_DAYS
    ids = Crm::MetaAdvisorAction.where(account_id: account_id, kind: 'scale_ad', status: :accepted,
                                       local_date: (local_date - (cooldown - 1))..local_date).pluck(:ad_id)
    { scale_accepted_ad_ids: ids.compact.uniq }
  end

  # { [kind, subject_key] => { id:, status:, position:, variant:, ad_id:, facts:, opened_at: } }
  def today(account_id, local_date)
    Crm::MetaAdvisorAction.where(account_id: account_id, local_date: local_date).to_h do |action|
      [[action.kind, action.subject_key],
       { id: action.id, status: action.status, position: action.position, variant: action.variant, ad_id: action.ad_id,
         facts: action.facts, opened_at: action.opened_at }]
    end
  end
end
