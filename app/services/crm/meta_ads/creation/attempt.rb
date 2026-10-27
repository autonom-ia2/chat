# A tentativa de criar um anúncio (#2198), uma linha de Crm::MetaAdsCreatedObject por chave de idempotência. Ela nasce
# `creating` antes da primeira chamada à Meta (a intenção fica gravada) e termina em:
#
# - `created`: anúncio criado e pausado; a mesma chave devolve o mesmo anúncio.
# - `rolled_back`: um passo falhou e o que tinha sido criado foi apagado ou arquivado. "Nada foi criado".
# - `rollback_failed`: nem apagar, nem procurar deu. O que ficou na Meta é desfeito antes de tentar de novo.
# - `unconfirmed`: a campanha ficou sem resposta (tempo esgotado ou falha da Meta) e a busca pela marca no nome veio
#   vazia. A Meta pode ter criado depois, ou ainda não mostrar na busca: a tela pede para conferir no Gerenciador de
#   Anúncios. A mesma chave procura de novo antes de criar; se achar, desfaz e refaz. Vazia de novo, continua
#   `unconfirmed`, por mais tempo que passe: sem a pessoa liberar, atraso da Meta não vira campanha duplicada. Ela
#   libera criar de novo (`recreate_unconfirmed`, só com uma linha `unconfirmed` desta chave) depois de conferir no
#   Gerenciador. Aí, se a campanha antiga aparecer mais tarde, as duas existem: a Auditoria guarda o nome com a marca
#   da tentativa antiga para achá-la.
#
# Nenhuma trava de banco fica presa durante uma chamada à Meta. Retomar começa por um UPDATE condicional na situação
# lida (compare-and-set) que leva a linha para `creating`; só quem ganha desfaz o que ficou e cria. Quem perde recebe
# `in_progress`. Se desfazer falhar, a linha volta para a situação de antes.
class Crm::MetaAds::Creation::Attempt
  # Sem sinal de vida há mais que isso: o processo que criava caiu (cada passo renova a linha antes de chamar a Meta, e
  # cada chamada desiste em Meta::AdsGraphClient::TIMEOUT_SECONDS).
  STALE_AFTER = 10.minutes
  LEFTOVER_STATUSES = %w[creating rollback_failed unconfirmed].freeze
  ROLLBACK_STATUSES = { undone: 'rolled_back', none: 'unconfirmed', failed: 'rollback_failed' }.freeze
  RECREATED_ACTION = 'meta_ads_create_recreated'.freeze

  def initialize(connection, client, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @undo = Crm::MetaAds::Creation::CampaignUndo.new(client, connection.ad_account_id)
  end

  # A linha da tentativa, pronta para criar, ou já criada. `recreate`: a pessoa conferiu no Gerenciador de Anúncios
  # que a campanha da tentativa não confirmada não está lá e pediu para criar de novo.
  def claim!(key, attributes, recreate: false)
    ensure_recreatable!(key) if recreate
    record, claimed = find_or_claim(key, attributes)
    claimed || record.status == 'created' ? record : recover!(record, recreate)
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

  # [linha, nasceu agora?]. A corrida pela mesma chave (outro pedido criou a linha no mesmo instante) é "em andamento".
  def find_or_claim(key, attributes)
    claimed = false
    record = Crm::MetaAdsCreatedObject.find_or_create_by!(account: @account, idempotency_key: key) do |row|
      row.assign_attributes(attributes.merge(user_id: @user&.id, ad_account_id: @connection.ad_account_id))
      claimed = true
    end
    [record, claimed]
  rescue ActiveRecord::RecordNotUnique
    raise Crm::MetaAds::Creation::Error, 'in_progress'
  rescue ActiveRecord::RecordInvalid => e
    # Só a unicidade da chave é "em andamento"; o resto é erro real.
    raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

    raise Crm::MetaAds::Creation::Error, 'in_progress'
  end

  # Recriar só vale para uma tentativa desta chave que está `unconfirmed`. Outra em andamento: `in_progress`.
  def ensure_recreatable!(key)
    status = Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: key)&.status
    raise Crm::MetaAds::Creation::Error, 'in_progress' if status == 'creating'
    raise Crm::MetaAds::Creation::Error, 'invalid_params' unless status == 'unconfirmed'
  end

  def recover!(record, recreate)
    status = record.status
    raise Crm::MetaAds::Creation::Error, 'in_progress' if status == 'creating' && record.updated_at >= STALE_AFTER.ago

    take!(record, status)
    clear_leftover!(record, status, recreate) if LEFTOVER_STATUSES.include?(status)
    record.update!(error_code: nil, campaign_id: nil, adset_id: nil, creative_id: nil, ad_id: nil)
    record
  end

  # Já com a linha em `creating`: confere na Meta e desfaz o que ficou da tentativa anterior. Se não der, a linha volta
  # para a situação de antes, com os ids que tinha.
  def clear_leftover!(record, status, recreate)
    outcome = @undo.undo(record, unknown: true)
    raise Crm::MetaAds::Creation::Error.new('meta_unavailable', nothing_created: false) if outcome == :failed
    return unless outcome == :none && status == 'unconfirmed'
    raise unconfirmed_error unless recreate

    audit_recreate!(record)
  rescue StandardError
    record.update!(status: status)
    raise
  end

  # Leva a linha para `creating` só se ninguém mexeu nela desde a leitura.
  def take!(record, status)
    taken = Crm::MetaAdsCreatedObject.where(id: record.id, status: status, updated_at: record.updated_at)
                                     .update_all(status: 'creating', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    raise Crm::MetaAds::Creation::Error, 'in_progress' unless taken == 1

    record.reload
  end

  # A pessoa liberou criar de novo uma tentativa não confirmada. Guarda o nome com a marca da tentativa antiga: se a
  # campanha dela aparecer depois, é por ele que se acha no Gerenciador. Sem a Auditoria gravada, não libera.
  def audit_recreate!(record)
    Audited.audit_class.create!(
      auditable: @account, user: @user, action: RECREATED_ACTION,
      audited_changes: { 'idempotency_key' => record.idempotency_key, 'name' => record.name,
                         'mark' => Crm::MetaAds::Creation::CampaignUndo.mark(record),
                         'campaign_name' => Crm::MetaAds::Creation::CampaignUndo.name_for(record),
                         'campaign_id' => record.campaign_id, 'attempt_started_at' => record.created_at&.iso8601 }.compact
    )
  end

  def unconfirmed_error
    Crm::MetaAds::Creation::Error.new('unconfirmed', nothing_created: false)
  end
end
