require 'rails_helper'

# A tela esconde Enviar ao CRM de quem o servidor recusaria (#682). O payload das configurações diz o que o próprio
# servidor decide: Crm::CardPolicy#create?. O "Adicionar à campanha" saiu com o segmento por etiqueta (#2695), e com ele
# o can_manage_campaigns.
RSpec.describe 'Autonomia prospecting settings permissions', type: :request do
  let(:account) { create(:account) }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/settings" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def permissions_for(user)
    get settings_url, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload']
  end

  it 'administrador pode enviar ao CRM' do
    expect(permissions_for(create(:user, :administrator, account: account))).to include('can_send_to_crm' => true)
  end

  it 'papel só com a prospecção não pode enviar ao CRM' do
    expect(permissions_for(agent_with(['prospecting_view']))).to include('can_send_to_crm' => false)
  end

  it 'papel com crm_manage_cards pode enviar ao CRM' do
    expect(permissions_for(agent_with(%w[prospecting_manage crm_manage_cards]))).to include('can_send_to_crm' => true)
  end

  it 'o payload não diz mais nada de campanha' do
    expect(permissions_for(agent_with(%w[prospecting_manage campaign_manage]))).not_to have_key('can_manage_campaigns')
  end
end
