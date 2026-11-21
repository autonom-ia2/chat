# #3106 — a conexão OAuth feita na tela de consentimento nova vale para todas as contas que a pessoa administra; a feita
# antes valia para a conta escolhida. A coluna guarda qual das duas promessas a pessoa aceitou: o servidor a liga no
# consentimento novo (Api::V1::Oauth::AuthorizationsController#pre_auth_params), e o Doorkeeper a copia do grant para o
# token e de um token para o seguinte na renovação (`custom_access_token_attributes`).
#
# Padrão false: toda conexão que já existe, e toda que o código anterior emitir durante o deploy blue-green, segue
# valendo só para a conta dela, sem revogar nada. O código anterior ignora a coluna.
class AddAllAccountsToOauthTokens < ActiveRecord::Migration[7.2]
  def change
    add_column :oauth_access_grants, :all_accounts, :boolean, default: false, null: false
    add_column :oauth_access_tokens, :all_accounts, :boolean, default: false, null: false
  end
end
