# Leads de um formulário que o banco recusou (#2740), lembrados por TTL para a reconciliação de hora em hora não os
# tentar de novo a cada rodada. Só a reconciliação pula quem está aqui; o "trazer quem já preencheu" (ação de uma
# pessoa) tenta sempre.
#
# TTL menor que a janela da reconciliação (48 h): o lead tem uma segunda tentativa dentro dela, para o caso de o defeito
# ter sido corrigido (deploy, funil consertado).
#
# A recusa fica presa à linha do formulário como foi lida junto com o destino (updated_at): o destino salvo de novo,
# mesmo igual, faz a rodada seguinte tentar de novo todos os recusados. Uma rodada que leu o destino antigo grava a
# recusa na versão antiga, e o destino novo não herda. Cache fora do ar: nada fica lembrado, e o lead só é tentado de
# novo. O tipo da recusa (Importer#refusal_kind, #2804) diz quando ela deixa de valer:
#
# - :lead — o dado do próprio lead. O prazo a solta, ou qualquer mudança na linha do formulário (destino salvo de novo,
#   o nome dele, o "trazer" de arquivado): no máximo uma tentativa a mais, e o dado ruim é recusado de novo.
# - :destination — o funil ou a etapa que o card não aceita. Presa também ao funil e à etapa como foram lidos: consertar
#   um deles (o updated_at muda) solta o lead, sem precisar salvar o destino de novo.
# - :transient — corrida no banco. Não fica lembrada: a rodada seguinte tenta sozinha. Na TRANSIENT_ATTEMPTS-ésima
#   vira recusa do lead, para não voltar o laço de cada hora que a #2740 fechou. A conta dura a janela inteira da
#   reconciliação (ATTEMPTS_TTL): vencido o prazo da recusa, uma falha a mais já a grava de novo. O webhook também
#   conta (a falha dele é a primeira tentativa).
class Crm::MetaAds::LeadForms::RefusedLeads
  TTL = 1.day
  TRANSIENT_ATTEMPTS = 3
  # Maior que a janela de 48 h da reconciliação: o lead sai dela antes de a conta zerar.
  ATTEMPTS_TTL = 3.days

  def initialize(form_record)
    base = ['crm_meta_ads_lead_forms', 'refused_lead', form_record.account_id, form_record.form_id.to_s, stamp(form_record)]
    @scopes = {
      lead: [*base, 'lead'],
      destination: [*base, 'destination', stamp(form_record.pipeline), stamp(form_record.stage)],
      transient: [*base, 'transient']
    }
  end

  def remember!(leadgen_id, kind)
    return transient!(leadgen_id) if kind == :transient

    Rails.cache.write(key(kind == :destination ? :destination : :lead, leadgen_id), true, expires_in: TTL)
  end

  # Dos leadgen_ids dados, os recusados há menos de TTL, pelo lead ou por este destino, nesta versão do formulário.
  def ids(leadgen_ids)
    keys = leadgen_ids.each_with_object({}) do |id, map|
      map[key(:lead, id)] = id.to_s
      map[key(:destination, id)] = id.to_s
    end
    Rails.cache.read_multi(*keys.keys).keys.map { |found| keys[found] }.uniq
  end

  private

  # Ler e gravar não é atômico: a trava da rodada (ReconcileScheduleJob) deixa uma leitura por formulário por vez, e o
  # webhook junto dela no mesmo lead só faz a conta errar por um.
  def transient!(leadgen_id)
    attempts = Rails.cache.read(key(:transient, leadgen_id)).to_i + 1
    Rails.cache.write(key(:transient, leadgen_id), attempts, expires_in: ATTEMPTS_TTL)
    remember!(leadgen_id, :lead) if attempts >= TRANSIENT_ATTEMPTS
  end

  def stamp(record)
    record&.updated_at&.utc&.iso8601(6)
  end

  def key(kind, leadgen_id)
    [*@scopes.fetch(kind), leadgen_id.to_s]
  end
end
