# Confere um token de leitura de anúncios antes de gravar (#1034, #1069): a Meta respondeu? o token vale?
# tem ads_read? enxerga alguma conta de anúncios? Sem conta atribuída o token "funciona", mas nenhum nome
# aparece: melhor recusar já aqui. Vale para a chave colada e para o token do "Entrar com o Facebook".
#
# Devolve nil quando o token serve, ou o código de erro que a tela traduz.
class Crm::MetaAds::TokenCheck
  def self.error_for(token)
    new(Meta::AdsGraphClient.new(access_token: token)).error
  end

  def initialize(client)
    @client = client
  end

  def error
    permissions = @client.permissions
    return graph_failure(permissions) unless permissions.ok
    return 'missing_ads_read' unless Meta::AdsGraphClient.ads_read_granted?(permissions.data)

    accounts = @client.ad_accounts_sample
    return graph_failure(accounts) unless accounts.ok

    'no_ad_account' if Array(accounts.data.to_h['data']).empty?
  end

  private

  def graph_failure(result)
    return 'meta_unavailable' if result.transient?
    return 'missing_ads_read' if result.scope_error?

    'invalid_token'
  end
end
