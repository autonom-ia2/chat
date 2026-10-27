# Se o token da conexão pode criar anúncio (#2198): token do próprio cliente (modos `token` e `facebook_login`) com
# `ads_management` e `pages_manage_ads`. No modo `partner` o usuário do sistema da plataforma só tem "Ver desempenho":
# a pessoa entra com o Facebook antes do primeiro passo.
class Crm::MetaAds::Creation::Access
  REQUIRED = %w[ads_management pages_manage_ads].freeze

  def initialize(connection)
    @connection = connection
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def can_create?
    @connection.own_token? && (REQUIRED - granted).empty?
  end

  # Mudar orçamento, datas e situação de anúncio que já existe: só `ads_management`.
  def can_change_ads?
    @connection.own_token? && granted.include?('ads_management')
  end

  private

  def granted
    return @granted if defined?(@granted)

    result = client.permissions
    # Queda da Meta não é falta de permissão: não manda a pessoa entrar de novo nem guarda a resposta.
    raise Crm::MetaAds::Creation::Error, 'meta_unavailable' if result.transient?

    @granted = Array(result.ok ? result.data.to_h['data'] : nil).filter_map do |entry|
      entry['permission'] if entry.is_a?(Hash) && entry['status'] == Meta::AdsGraphClient::GRANTED
    end
  end
end
