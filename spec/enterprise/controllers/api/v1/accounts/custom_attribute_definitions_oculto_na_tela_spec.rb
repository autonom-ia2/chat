require 'rails_helper'

# #2435: quem tem a chave de atributos numa função personalizada também esconde e mostra o atributo. Fica em
# spec/enterprise porque a metade da função personalizada do AccountUser#permission_granted? só existe com o EE.
RSpec.describe 'Custom Attribute Definitions API: oculto_na_tela com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:definicao) { create(:custom_attribute_definition, account: account) }

  def pessoa_com(*permissoes)
    user = create(:user, account: account, role: :agent)
    funcao = create(:custom_role, account: account, permissions: permissoes)
    user.account_users.find_by(account: account).update!(custom_role: funcao)
    user
  end

  def esconder(user)
    patch "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{definicao.id}",
          headers: user.create_new_auth_token, params: { custom_attribute_definition: { oculto_na_tela: true } }, as: :json
  end

  # MOTIVO: a chave `attribute_manage` vale para esconder, como vale para editar o resto do atributo.
  it 'com attribute_manage esconde' do
    esconder(pessoa_com('attribute_manage'))

    expect(response).to have_http_status(:success)
    expect(definicao.reload.oculto_na_tela).to be(true)
  end

  # MOTIVO: outra chave de configuração não basta.
  it 'sem attribute_manage não muda' do
    esconder(pessoa_com('label_manage'))

    expect(response).to have_http_status(:unauthorized)
    expect(definicao.reload.oculto_na_tela).to be(false)
  end
end
