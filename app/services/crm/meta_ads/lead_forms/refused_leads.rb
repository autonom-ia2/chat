# Leads de um formulário que o banco recusou (#2740), lembrados por TTL para a reconciliação de hora em hora não os
# tentar de novo a cada rodada. Só a reconciliação pula quem está aqui; o "trazer quem já preencheu" (ação de uma
# pessoa) tenta sempre.
#
# TTL menor que a janela da reconciliação (48 h): o lead tem uma segunda tentativa dentro dela, para o caso de o defeito
# ter sido corrigido (deploy, funil consertado). No máximo duas tentativas, e duas idas ao rastreador, por lead.
#
# A recusa pode ser do próprio lead ou do destino (funil ou etapa que o card não aceita). Por isso ela fica presa à
# linha do formulário como foi lida junto com o destino (updated_at). Qualquer mudança na linha (o destino salvo de
# novo, mesmo igual, o nome, o "trazer" de arquivado) faz a rodada seguinte tentar de novo todos os recusados. Uma
# rodada que leu o destino antigo grava a recusa na versão antiga, e o destino novo não herda. Cache fora do ar: nada
# fica lembrado, e o lead só é tentado de novo.
#
# Risco conhecido: recusa passageira (corrida de unicidade no contato, que o lock_person! do Importer quase elimina)
# também fica lembrada até o TTL.
class Crm::MetaAds::LeadForms::RefusedLeads
  TTL = 1.day

  def initialize(form_record)
    @scope = ['crm_meta_ads_lead_forms', 'refused_lead', form_record.account_id, form_record.form_id.to_s,
              form_record.updated_at&.utc&.iso8601(6)]
  end

  def remember!(leadgen_id)
    Rails.cache.write(key(leadgen_id), true, expires_in: TTL)
  end

  # Dos leadgen_ids dados, os recusados há menos de TTL nesta versão do formulário.
  def ids(leadgen_ids)
    keys = leadgen_ids.to_h { |id| [key(id), id.to_s] }
    Rails.cache.read_multi(*keys.keys).keys.map { |found| keys[found] }
  end

  private

  def key(leadgen_id)
    [*@scope, leadgen_id.to_s]
  end
end
