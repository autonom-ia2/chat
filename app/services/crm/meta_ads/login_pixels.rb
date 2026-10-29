# Quais Pixels a pessoa marcou na janela do "Entrar com o Facebook" (#2343). O Login do Facebook para Empresas
# entrega um token do usuário do sistema da integração, que só acessa os ativos marcados; a lista de Pixels da
# conta de anúncios, porém, traz todos. A única leitura documentada que separa os marcados é
# GET /{pixel}/assigned_users?business=<portfólio do cliente>: o Pixel marcado tem esse usuário do sistema.
#
# `granted` em cada Pixel: true/false quando a Meta respondeu e pelo menos um veio marcado; nil quando não deu para
# saber (a tela então fica com o de disparo mais recente e oferece "Alterar"). O log diz qual caminho valeu, só com
# contagens e o código da recusa da Meta.
class Crm::MetaAds::LoginPixels
  MAX_LOOKUPS = 10

  def initialize(client)
    @client = client
  end

  def mark(pixels)
    granted = granted_ids(pixels)
    log(pixels.size, granted)
    pixels.map { |pixel| pixel.merge(granted: granted&.include?(pixel[:id])) }
  end

  private

  def granted_ids(pixels)
    return unknown('no_pixels') if pixels.empty?
    return unknown('too_many') if pixels.size > MAX_LOOKUPS

    user_id, business_id = identity
    user_id && assigned_ids(pixels, user_id, business_id)
  end

  def assigned_ids(pixels, user_id, business_id)
    results = pixels.map { |pixel| [pixel[:id], @client.pixel_assigned_users(pixel[:id], business_id)] }
    failed = results.map(&:last).find { |result| !result.ok }
    return unknown("assigned_users code=#{failed.error_code.inspect}") if failed

    with_user(results, user_id).presence || unknown('none_assigned')
  end

  def with_user(results, user_id)
    results.filter_map { |id, result| id if assigned?(result, user_id) }
  end

  def identity
    result = @client.login_identity
    return unknown("me code=#{result.error_code.inspect}") unless result.ok

    ids = result.data.to_h.values_at('id', 'client_business_id').map(&:to_s)
    ids.all?(&:present?) ? ids : unknown('no_client_business')
  end

  def assigned?(result, user_id)
    Array(result.data.to_h['data']).any? { |row| row['id'].to_s == user_id }
  end

  def unknown(reason)
    @reason = reason
    nil
  end

  def log(total, granted)
    detail = granted ? "source=assigned_users granted=#{granted.size}" : "source=latest reason=#{@reason}"
    Rails.logger.info("[MetaAdsLogin] pixels total=#{total} #{detail}")
  end
end
