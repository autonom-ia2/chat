require 'rails_helper'

# #2124 (decisão J): toda chave de editar o CRM traz o Ver CRM. A função é gravada com `crm_view`
# (CustomRole::CRM_EDITING_KEYS), então quem só recebeu uma chave de editar abre o quadro e o card. Relatórios
# (`crm_view_reports`) e valores em R$ (`sales_value_view`) continuam à parte.
RSpec.describe 'Chave de editar o CRM traz o Ver CRM', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def list_pipelines
    pipeline
    get "#{base}/pipelines", headers: agent.create_new_auth_token, as: :json
  end

  CustomRole::CRM_EDITING_KEYS.each do |key|
    it "abre os funis com só #{key}" do
      give_role([key])

      list_pipelines

      expect(response).to have_http_status(:ok)
    end
  end

  it 'nega os funis a quem não tem chave do CRM' do
    give_role(%w[contact_view])

    list_pipelines

    expect(response).to have_http_status(:unauthorized)
  end

  it 'nega os funis a quem só vê relatórios' do
    give_role(%w[crm_view_reports])

    list_pipelines

    expect(response).to have_http_status(:unauthorized)
  end

  it 'nega os funis a quem só vê valores em R$' do
    give_role(%w[sales_value_view])

    list_pipelines

    expect(response).to have_http_status(:unauthorized)
  end
end
