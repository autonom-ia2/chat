# Login único (#2338): o token da Página escolhida, a partir do token que o "Entrar com o Facebook" dos Anúncios gravou.
#
# É o único ponto que depende do tipo de token da configuração do login (META_ADS_LOGIN_CONFIGURATION_ID): token de
# pessoa ou de usuário do sistema. Hoje lê `GET /{page_id}?fields=access_token` com o token da conexão, que serve aos
# dois quando a Página foi concedida. O teste no app de teste (roteiro na #2338) confirma; mudando, muda só aqui.
#
# O token da conexão vai junto como `user_access_token` da caixa (o campo é obrigatório e é com ele que a caixa se
# reautoriza). Nenhum token sai daqui em log, erro ou resposta.
class Crm::MetaAds::LoginUnico::TokenDaPagina
  def initialize(connection)
    @connection = connection
  end

  # { page: 'EAA...', user: 'EAA...' }, ou nil quando a Meta não entrega o token da Página para este login.
  def call(page_id)
    result = Meta::AdsGraphClient.new(access_token: @connection.read_token).page_access_token(page_id)
    page_token = result.data.to_h['access_token'].presence if result.ok
    return if page_token.blank?

    { page: page_token, user: @connection.read_token }
  end
end
