require 'rails_helper'

# #2308, decisão 11: a recusa 401 de /custom_roles diz o motivo no corpo, no formato das outras recusas do controller
# ({ error:, message: }). O status e a regra não mudam; a tela de Funções guiadas mostra uma frase por código.
RSpec.describe 'Custom role refusal codes (#2308)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:builder_role) { create(:custom_role, account: account, permissions: %w[custom_role_manage contact_view]) }
  let!(:builder) do
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account: account).update!(custom_role: builder_role)
    user
  end

  # A mensagem é comparada com o texto literal do en.yml, não com o I18n.t do próprio teste: se a chave sumir, os dois
  # lados virariam 'Translation missing' e o teste passaria.
  let(:messages) do
    {
      'feature_off' => 'Team roles are not available on this account right now.',
      'own_role' => 'Nobody changes their own role.',
      'out_of_reach' => "You can't give part of this role. Ask the administrator."
    }
  end

  before { account.enable_features!('custom_roles') }

  def create_role(as:, permissions:)
    post "/api/v1/accounts/#{account.id}/custom_roles",
         params: { custom_role: { name: 'Nova', permissions: permissions } },
         headers: as.create_new_auth_token, as: :json
  end

  def update_role(role, as:)
    put "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}",
        params: { custom_role: { name: 'Outro nome' } },
        headers: as.create_new_auth_token, as: :json
  end

  def expect_refusal(code)
    expect(response).to have_http_status(:unauthorized)
    expect(Api::V1::Accounts::CustomRolesController::UNAUTHORIZED_CODES).to include(code)
    expect(response.parsed_body).to eq('error' => code, 'message' => messages.fetch(code))
  end

  # Rodada 5: todo código de um 401 daqui está numa lista só (os do GrantGuard e o feature_off), e cada um tem
  # mensagem. A tela lê a mesma lista (codigosDo401.spec.js).
  it 'lists every 401 code once, frozen, each with its message' do
    codes = Api::V1::Accounts::CustomRolesController::UNAUTHORIZED_CODES

    expect(codes).to eq([*CustomRoles::GrantGuard::CODES, 'feature_off'])
    expect(codes).to be_frozen
    expect(messages.keys).to match_array(codes)
  end

  # Controle positivo: o GrantGuard não recusa tudo; dentro do alcance, quem monta cria.
  it 'lets the builder create a role within reach' do
    expect { create_role(as: builder, permissions: %w[contact_view]) }.to change(CustomRole, :count).by(1)
    expect(response).to have_http_status(:ok)
  end

  it "answers 'feature_off' when the account does not have custom roles, and logs the refusal" do
    account.disable_features!('custom_roles')
    allow(Rails.logger).to receive(:info).and_call_original

    expect { create_role(as: admin, permissions: %w[contact_view]) }.not_to change(CustomRole, :count)
    expect_refusal('feature_off')
    expect(Rails.logger).to have_received(:info).with('custom_roles: recusa feature_off (recurso desligado na conta)')
  end

  it "answers 'feature_off' to the builder too when the account does not have custom roles" do
    account.disable_features!('custom_roles')

    get "/api/v1/accounts/#{account.id}/custom_roles", headers: builder.create_new_auth_token, as: :json

    expect_refusal('feature_off')
  end

  it "answers 'own_role' when someone who is not an administrator changes the role they hold" do
    update_role(builder_role, as: builder)

    expect_refusal('own_role')
    expect(builder_role.reload.name).not_to eq('Outro nome')
  end

  it "answers 'out_of_reach' for keys the giver does not hold and for a role above them" do
    expect { create_role(as: builder, permissions: %w[contact_view crm_export]) }.not_to change(CustomRole, :count)
    expect_refusal('out_of_reach')

    above = create(:custom_role, account: account, name: 'Financeiro', permissions: %w[financial_view])
    update_role(above, as: builder)
    expect_refusal('out_of_reach')
    expect(above.reload.name).to eq('Financeiro')

    delete "/api/v1/accounts/#{account.id}/custom_roles/#{above.id}", headers: builder.create_new_auth_token, as: :json
    expect_refusal('out_of_reach')
    expect(CustomRole.exists?(above.id)).to be(true)
  end

  it 'keeps the generic refusal, without a code, for whoever cannot build roles' do
    plain_agent = create(:user, account: account, role: :agent)

    create_role(as: plain_agent, permissions: %w[contact_view])

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    expect(response.parsed_body).not_to have_key('message')
  end

  # Quem não gerencia funções não fica sabendo do plano: com o recurso desligado, a recusa continua a genérica.
  it 'keeps the generic refusal for whoever cannot build roles when the account does not have custom roles' do
    plain_agent = create(:user, account: account, role: :agent)
    account.disable_features!('custom_roles')

    get "/api/v1/accounts/#{account.id}/custom_roles", headers: plain_agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
  end
end
