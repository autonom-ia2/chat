# Desfazer a campanha de uma tentativa de criar (#2198). O nome da campanha leva a marca da tentativa
# ("Nome [1a2b3c4d]", os 8 primeiros caracteres da chave de idempotência), gravada antes da primeira chamada. Assim, se a
# resposta da criação se perde (tempo esgotado) ou o id não chega a ser gravado, a campanha ainda é achada na Meta.
#
# `undo` apaga a campanha (o grupo e o anúncio vão junto) ou, se a Meta não deixar, arquiva. Devolve:
# - `:undone`: a Meta ficou como estava (apagou ou arquivou; ou a Meta recusou a campanha, e não havia o que desfazer);
# - `:none`: a campanha ficou sem resposta e a busca pela marca veio vazia. A Meta pode ter criado depois, ou ainda não
#   mostrar na busca: não é "nada criado" (Crm::MetaAds::Creation::Attempt decide o que fazer);
# - `:failed`: não deu para apagar, arquivar ou procurar.
class Crm::MetaAds::Creation::CampaignUndo
  MARK_LENGTH = 8
  GONE_STATUSES = %w[DELETED ARCHIVED].freeze

  def self.name_for(record)
    "#{record.name} [#{mark(record)}]"
  end

  def self.mark(record)
    record.idempotency_key.first(MARK_LENGTH)
  end

  def initialize(client, ad_account_id)
    @client = client
    @ad_account_id = ad_account_id
  end

  # `unknown`: a campanha ficou sem resposta e pode existir sem id. Sem isso e sem id, a Meta recusou: nada a desfazer.
  def undo(record, unknown:)
    return remove([record.campaign_id]) if record.campaign_id.present?
    return :undone unless unknown

    ids = campaigns_of(record)
    return :failed if ids.nil?

    ids.empty? ? :none : remove(ids)
  end

  private

  def remove(ids)
    ids.all? { |id| @client.delete_object(id).ok || @client.update_object(id, status: 'ARCHIVED').ok } ? :undone : :failed
  end

  # Ids das campanhas vivas com o nome desta tentativa; nil quando a Meta não respondeu.
  def campaigns_of(record)
    name = self.class.name_for(record)
    result = @client.campaigns_named(@ad_account_id, self.class.mark(record))
    return unless result.ok

    Array(result.data['data']).filter_map do |campaign|
      campaign['id'].to_s if campaign['name'] == name && GONE_STATUSES.exclude?(campaign['effective_status'])
    end
  end
end
