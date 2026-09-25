require 'rails_helper'

# A tela esconde Enviar ao CRM e Adicionar à campanha de quem o servidor recusaria (#682). O payload das configurações
# diz o que o próprio servidor decide: Crm::CardPolicy#create? para o CRM e campaign_manage para a campanha.
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
    response.parsed_body['payload'].slice('can_send_to_crm', 'can_manage_campaigns')
  end

  it 'administrador pode enviar ao CRM e mexer em campanha' do
    expect(permissions_for(create(:user, :administrator, account: account)))
      .to eq('can_send_to_crm' => true, 'can_manage_campaigns' => true)
  end

  it 'papel só com a prospecção não pode nenhum dos dois' do
    expect(permissions_for(agent_with(['prospecting_view'])))
      .to eq('can_send_to_crm' => false, 'can_manage_campaigns' => false)
  end

  it 'papel com crm_manage_cards pode enviar ao CRM, sem campanha' do
    expect(permissions_for(agent_with(%w[prospecting_manage crm_manage_cards])))
      .to eq('can_send_to_crm' => true, 'can_manage_campaigns' => false)
  end

  it 'papel com campaign_manage mexe em campanha, sem CRM' do
    expect(permissions_for(agent_with(%w[prospecting_manage campaign_manage])))
      .to eq('can_send_to_crm' => false, 'can_manage_campaigns' => true)
  end
end
