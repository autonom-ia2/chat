# A tentativa de criar um anúncio (#2198), uma linha de Crm::MetaAdsCreatedObject por chave de idempotência. Ela nasce
# `creating` antes da primeira chamada à Meta (a intenção fica gravada) e termina em:
#
# - `created`: anúncio criado e pausado; a mesma chave devolve o mesmo anúncio.
# - `rolled_back`: um passo falhou e o que tinha sido criado foi apagado ou arquivado. "Nada foi criado".
# - `rollback_failed`: nem apagar, nem procurar deu. O que ficou na Meta é desfeito antes de tentar de novo.
# - `unconfirmed`: a campanha ficou sem resposta (tempo esgotado ou falha da Meta) e a busca pela marca no nome veio
#   vazia. A Meta pode ter criado depois, ou ainda não mostrar na busca: a tela pede para conferir no Gerenciador de
#   Anúncios. A mesma chave procura de novo antes de criar: se achar, desfaz e refaz; vazia de novo, só cria depois de
#   STALE_AFTER.
class Crm::MetaAds::Creation::Attempt
  # Sem sinal de vida há mais que isso: o processo que criava caiu (cada passo renova a linha antes de chamar a Meta, e
  # cada chamada desiste em Meta::AdsGraphClient::TIMEOUT_SECONDS). Também é a espera de uma tentativa não confirmada.
  STALE_AFTER = 10.minutes
  LEFTOVER_STATUSES = %w[creating rollback_failed unconfirmed].freeze
  ROLLBACK_STATUSES = { undone: 'rolled_back', none: 'unconfirmed', failed: 'rollback_failed' }.freeze

  def initialize(connection, client, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @undo = Crm::MetaAds::Creation::CampaignUndo.new(client, connection.ad_account_id)
  end

  # A linha da tentativa. Nova ou já criada: devolve. Em andamento por outro pedido: recusa. Falhou antes, ficou presa
  # ou não confirmada: confere na Meta, desfaz o que ficou e devolve pronta para criar de novo.
  def claim!(key, attributes)
    claimed = false
    record = Crm::MetaAdsCreatedObject.find_or_create_by!(account: @account, idempotency_key: key) do |row|
      row.assign_attributes(attributes.merge(user_id: @user&.id, ad_account_id: @connection.ad_account_id))
      claimed = true
    end
    claimed || record.status == 'created' ? record : recover!(record)
  rescue ActiveRecord::RecordNotUnique
    raise Crm::MetaAds::Creation::Error, 'in_progress'
  rescue ActiveRecord::RecordInvalid => e
    # Só a corrida pela mesma chave (outro pedido criou a linha no mesmo instante) é "em andamento"; o resto é erro real.
    raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

    raise Crm::MetaAds::Creation::Error, 'in_progress'
  end

  # Um passo falhou. `unknown`: a campanha ficou sem resposta e pode existir mesmo sem id. Devolve o erro para a tela,
  # com `nothing_created` só quando a Meta comprovadamente ficou como estava.
  def rollback!(record, error, unknown:)
    outcome = @undo.undo(record, unknown: unknown)
    record.update!(status: ROLLBACK_STATUSES.fetch(outcome), error_code: error.code)
    return unconfirmed_error if outcome == :none

    Crm::MetaAds::Creation::Error.new(error.code, nothing_created: outcome == :undone)
  end

  private

  # Com a linha travada, para dois pedidos com a mesma chave não refazerem juntos. `rolled_back` já foi desfeito.
  def recover!(record)
    record.with_lock do
      return record if record.status == 'created'

      fresh = record.updated_at >= STALE_AFTER.ago
      raise Crm::MetaAds::Creation::Error, 'in_progress' if record.status == 'creating' && fresh

      clear_leftover!(record, fresh) if LEFTOVER_STATUSES.include?(record.status)
      record.update!(status: 'creating', error_code: nil, campaign_id: nil, adset_id: nil, creative_id: nil, ad_id: nil)
    end
    record
  end

  def clear_leftover!(record, fresh)
    outcome = @undo.undo(record, unknown: true)
    raise Crm::MetaAds::Creation::Error.new('meta_unavailable', nothing_created: false) if outcome == :failed
    raise unconfirmed_error if outcome == :none && record.status == 'unconfirmed' && fresh
  end

  def unconfirmed_error
    Crm::MetaAds::Creation::Error.new('unconfirmed', nothing_created: false)
  end
end
