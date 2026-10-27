# A tentativa de criar um anúncio (#2198), uma linha de Crm::MetaAdsCreatedObject por chave de idempotência. Ela nasce
# `creating` antes da primeira chamada à Meta (a intenção fica gravada) e termina em:
#
# - `created`: anúncio criado e pausado; a mesma chave devolve o mesmo anúncio.
# - `rolled_back`: um passo falhou e o que tinha sido criado foi apagado ou arquivado. "Nada foi criado".
# - `rollback_failed`: nem apagar, nem procurar deu. O que ficou na Meta é desfeito antes de tentar de novo.
# - `unconfirmed`: a campanha ficou sem resposta (tempo esgotado ou falha da Meta) e a busca pela marca no nome veio
#   vazia. A Meta pode ter criado depois, ou ainda não mostrar na busca: a tela pede para conferir no Gerenciador de
#   Anúncios. A mesma chave procura de novo antes de criar; se achar, desfaz e refaz. Vazia de novo, continua
#   `unconfirmed`, por mais tempo que passe. `creating` parado há mais que STALE_AFTER (o processo caiu) segue a mesma
#   regra: nunca cria sem saber. Com a campanha achada, desfaz e refaz; com a busca vazia, fica `unconfirmed` até a
#   pessoa recriar. A pessoa libera criar de novo (`recreate_unconfirmed`,
#   só com uma linha `unconfirmed` desta chave) depois de conferir no Gerenciador. Aí, se a campanha antiga aparecer
#   mais tarde, as duas existem: a Auditoria guarda o nome com a marca da tentativa antiga para achá-la.
#
# O mesmo pedido com outra chave (outra aba, outro aparelho, a tela reaberta) não cria a segunda campanha: cada linha
# guarda o SHA-256 do pedido validado (`request_digest`), e o índice único parcial em (conta, conta de anúncios, digest)
# para `creating`, `unconfirmed` e `rollback_failed` deixa só uma tentativa viva por pedido, mesmo com dois pedidos no
# mesmo instante. Quem bate na outra recebe a chave dela (Crm::MetaAds::Creation::Twin), e a tela segue com ela.
#
# Nenhuma trava de banco fica presa durante uma chamada à Meta. Retomar começa por um UPDATE condicional na situação
# lida (compare-and-set) que leva a linha para `creating`; só quem ganha desfaz o que ficou e cria. Quem perde recebe
# `in_progress`. Se desfazer falhar, a linha volta para a situação de antes.
class Crm::MetaAds::Creation::Attempt
  # Sem sinal de vida há mais que isso: o processo que criava caiu (cada passo renova a linha antes de chamar a Meta, e
  # cada chamada desiste em Meta::AdsGraphClient::TIMEOUT_SECONDS).
  STALE_AFTER = 10.minutes
  # O que ainda pode ter campanha viva na Meta: o mesmo conjunto do índice único parcial do digest.
  LEFTOVER_STATUSES = %w[creating rollback_failed unconfirmed].freeze
  # Sem saber se a Meta criou: só a pessoa libera criar de novo.
  UNCONFIRMED_LIKE = %w[unconfirmed creating].freeze
  ROLLBACK_STATUSES = { undone: 'rolled_back', none: 'unconfirmed', failed: 'rollback_failed' }.freeze
  RECREATED_ACTION = 'meta_ads_create_recreated'.freeze

  def initialize(connection, client, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @undo = Crm::MetaAds::Creation::CampaignUndo.new(client, connection.ad_account_id)
    @twin = Crm::MetaAds::Creation::Twin.new(@account, connection.ad_account_id)
  end

  # A linha da tentativa, pronta para criar, ou já criada. `recreate`: a pessoa conferiu no Gerenciador de Anúncios
  # que a campanha da tentativa não confirmada não está lá e pediu para criar de novo.
  def claim!(key, attributes, recreate: false)
    digest = attributes[:request_digest]
    recreate ? ensure_recreatable!(key) : @twin.check!(key, digest)
    record, claimed = locked_by_digest(key, digest) { find_or_claim(key, attributes) }
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
  # Sem find_or_create_by!: ele engole a violação de unicidade e procura pela chave, e a do digest sumiria.
  def find_or_claim(key, attributes)
    record = Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: key)
    return [record, false] if record

    row = Crm::MetaAdsCreatedObject.create!(attributes.merge(account: @account, idempotency_key: key, user_id: @user&.id,
                                                             ad_account_id: @connection.ad_account_id))
    [row, true]
  rescue ActiveRecord::RecordInvalid => e
    # Só a unicidade da chave é "em andamento"; o resto é erro real.
    raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

    raise Crm::MetaAds::Creation::Error, 'in_progress'
  end

  # Escrita que pode bater no índice único: a da mesma chave (corrida dos dois toques) ou a do mesmo pedido com outra
  # chave (Crm::MetaAds::Creation::Twin). Em savepoint, para a falha do INSERT/UPDATE não estragar quem está em volta.
  def locked_by_digest(key, digest, &)
    Crm::MetaAdsCreatedObject.transaction(requires_new: true, &)
  rescue ActiveRecord::RecordNotUnique
    @twin.check!(key, digest)
    raise Crm::MetaAds::Creation::Error, 'in_progress'
  end

  # Recriar só vale para uma tentativa desta chave que está `unconfirmed` (ou `creating` parada, que é o mesmo caso).
  # Outra em andamento: `in_progress`.
  def ensure_recreatable!(key)
    record = Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: key)
    raise Crm::MetaAds::Creation::Error, 'in_progress' if record && fresh_creating?(record)
    raise Crm::MetaAds::Creation::Error, 'invalid_params' unless record && UNCONFIRMED_LIKE.include?(record.status)
  end

  def fresh_creating?(record)
    record.status == 'creating' && record.updated_at >= STALE_AFTER.ago
  end

  def recover!(record, recreate)
    status = record.status
    raise Crm::MetaAds::Creation::Error, 'in_progress' if fresh_creating?(record)

    locked_by_digest(record.idempotency_key, record.request_digest) { take!(record, status) }
    clear_leftover!(record, status, recreate) if LEFTOVER_STATUSES.include?(status)
    record.update!(error_code: nil, campaign_id: nil, adset_id: nil, creative_id: nil, ad_id: nil)
    record
  end

  # Já com a linha em `creating`: confere na Meta e desfaz o que ficou da tentativa anterior. Se não der, a linha volta
  # para a situação de antes, com os ids que tinha; `creating` parado volta como `unconfirmed` (nunca cria sem saber).
  def clear_leftover!(record, status, recreate)
    outcome = @undo.undo(record, unknown: true)
    raise Crm::MetaAds::Creation::Error.new('meta_unavailable', nothing_created: false) if outcome == :failed
    return unless outcome == :none && UNCONFIRMED_LIKE.include?(status)
    raise unconfirmed_error unless recreate

    audit_recreate!(record)
  rescue StandardError
    record.update!(status: status == 'creating' ? 'unconfirmed' : status)
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
