# A tentativa gêmea (#2198): outra linha de Crm::MetaAdsCreatedObject, com outra chave, do mesmo pedido
# (`request_digest`, Crm::MetaAds::Creation::Draft#digest), na mesma conta e na mesma conta de anúncios, que ainda pode
# ter campanha viva na Meta (`creating`, `unconfirmed` ou `rollback_failed`). O índice único parcial
# `idx_crm_meta_ads_created_objects_digest` é a trava: só uma dessas existe por pedido. Este objeto acha a gêmea e diz à
# tela como seguir com ela, devolvendo a chave dela:
#
# - `creating` com sinal de vida: `in_progress`.
# - `creating` parado há mais que Crm::MetaAds::Creation::Attempt::STALE_AFTER, ou `unconfirmed`: `unconfirmed`. Nunca
#   cria sem saber: a tela segue com a chave dela, que, com a campanha achada, desfaz e refaz; com a busca vazia, fica
#   `unconfirmed` até a pessoa recriar ("Não está no Gerenciador, criar de novo").
# - `rollback_failed`: `meta_unavailable`, sem "nada criado". A mesma chave desfaz o que ficou antes de criar.
class Crm::MetaAds::Creation::Twin
  def initialize(account, ad_account_id)
    @account = account
    @ad_account_id = ad_account_id
  end

  def check!(key, digest)
    twin = find(key, digest)
    raise error_for(twin) if twin
  end

  def find(key, digest)
    return if digest.blank?

    Crm::MetaAdsCreatedObject.where(account: @account, ad_account_id: @ad_account_id, request_digest: digest,
                                    status: Crm::MetaAds::Creation::Attempt::LEFTOVER_STATUSES)
                             .where.not(idempotency_key: key).last
  end

  private

  def error_for(twin)
    Crm::MetaAds::Creation::Error.new(code_for(twin), nothing_created: false, attempt_key: twin.idempotency_key)
  end

  def code_for(twin)
    return 'meta_unavailable' if twin.status == 'rollback_failed'
    return 'in_progress' if twin.status == 'creating' && twin.updated_at >= Crm::MetaAds::Creation::Attempt::STALE_AFTER.ago

    'unconfirmed'
  end
end
