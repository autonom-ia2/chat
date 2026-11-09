# Desfazer a campanha de uma tentativa de criar (#2198). O nome da campanha leva a marca da tentativa
# ("Nome [1a2b3c4d]", os 8 primeiros caracteres da chave de idempotência; na cópia, "Origem - Cópia [1a2b3c4d]"),
# gravada antes da primeira chamada. Cada recriar da mesma chave (#2804) usa uma marca nova, tirada da chave e de quantas
# vezes ela foi recriada (a Auditoria `meta_ads_create_recreated` guarda cada vez, com a marca antiga): se a campanha
# antiga aparecer depois, a busca não confunde as duas. Assim, se a
# resposta da criação se perde (tempo esgotado) ou o id não chega a ser gravado, a campanha ainda é achada na Meta.
#
# `undo` apaga a campanha (o grupo e o anúncio vão junto) ou, se a Meta não deixar, arquiva. Devolve:
# - `:undone`: a Meta ficou como estava (apagou ou arquivou; ou a Meta recusou a campanha, e não havia o que desfazer);
# - `:none`: a campanha ficou sem resposta e a busca pela marca veio vazia. A Meta pode ter criado depois, ou ainda não
#   mostrar na busca: não é "nada criado" (Crm::MetaAds::Creation::Attempt decide o que fazer);
# - `:failed`: não deu para apagar, arquivar ou procurar.
#
# Campanha que já não existe na Meta (apagada pelo Gerenciador, por exemplo) conta como desfeita: senão a chave da
# tentativa ficaria presa em `rollback_failed` para sempre.
class Crm::MetaAds::Creation::CampaignUndo
  MARK_LENGTH = 8
  GONE_STATUSES = %w[DELETED ARCHIVED].freeze

  def self.name_for(record)
    "#{record.name} [#{mark(record)}]"
  end

  def self.mark(record)
    generation = recreations(record)
    return record.idempotency_key.first(MARK_LENGTH) if generation.zero?

    Digest::SHA256.hexdigest("#{record.idempotency_key}:#{generation}").first(MARK_LENGTH)
  end

  def self.recreations(record)
    Audited.audit_class.where(auditable_type: 'Account', auditable_id: record.account_id,
                              action: Crm::MetaAds::Creation::Attempt::RECREATED_ACTION)
           .where("audited_changes ->> 'idempotency_key' = ?", record.idempotency_key).count
  end

  def initialize(client, ad_account_id)
    @client = client
    @ad_account_id = ad_account_id
  end

  # `unknown`: a campanha ficou sem resposta e pode existir sem id. Sem isso e sem id, a Meta recusou: nada a desfazer.
  def undo(record, unknown:)
    return remove([record.campaign_id]) if record.campaign_id.present?
    return :undone unless unknown

    ids = live_campaigns(record)
    return :failed if ids.nil?

    ids.empty? ? :none : remove(ids)
  end

  # Ids das campanhas vivas com a marca desta tentativa; nil quando a Meta não respondeu. O nome termina com a marca (a
  # cópia, #2778, não escolhe o nome inteiro: a Meta junta o nome da origem com o fim que a cópia pede, e esse fim leva a
  # marca). A marca sai uma vez só por busca.
  def live_campaigns(record)
    mark = self.class.mark(record)
    result = @client.campaigns_named(@ad_account_id, mark)
    return unless result.ok

    Array(result.data['data']).filter_map do |campaign|
      campaign['id'].to_s if campaign['name'].to_s.end_with?(" [#{mark}]") && GONE_STATUSES.exclude?(campaign['effective_status'])
    end
  end

  # A campanha ainda existe e não foi apagada nem arquivada: true/false; nil quando a Meta não respondeu.
  def alive?(id)
    result = @client.object_status(id)
    return false if !result.ok && result.missing_object?
    return unless result.ok

    GONE_STATUSES.exclude?(result.data['effective_status'])
  end

  private

  def remove(ids)
    ids.all? { |id| removed?(id) } ? :undone : :failed
  end

  def removed?(id)
    @client.delete_object(id).ok || @client.update_object(id, status: 'ARCHIVED').ok || gone?(id)
  end

  # Relê a campanha: "objeto não existe" (100 com subcódigo 33; o 100 puro é parâmetro inválido e não prova nada) ou já
  # apagada/arquivada.
  def gone?(id)
    result = @client.object_status(id)
    return result.missing_object? unless result.ok

    GONE_STATUSES.include?(result.data['effective_status'])
  end
end
