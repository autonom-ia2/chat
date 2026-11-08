require 'rails_helper'

# #2070: a sugestão de etapas pela IA (meta_funnel_stages) é o segundo chamador da policy Crm::MetaAdsConnection
# :update?, fora do controller. Ela roda adiada, e a autorização vale de novo na execução: meta_ads_manage pode,
# meta_ads_view e o agente sem função, não. Fica em spec/enterprise: a metade de função do permission_granted? é EE.
RSpec.describe Crm::Ai::InteractiveOperation do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let!(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Viagem').first }

  before do
    create_meta_ads_insights_connection(account)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: whatsapp_inbox)
  end

  def membership(permissions = nil)
    user = create(:user, account: account, role: :agent)
    account_user = AccountUser.find_by(account: account, user: user)
    account_user.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) if permissions
    account_user
  end

  def operation_for(account_user)
    described_class.new('operation' => 'meta_funnel_stages', 'inputs' => { 'pipeline_id' => pipeline.id, 'language' => 'pt_BR' },
                        'account_id' => account.id, 'account_user_id' => account_user.id)
  end

  it 'deixa quem tem meta_ads_manage pedir a sugestão de etapas' do
    expect { operation_for(membership(%w[meta_ads_manage])).authorize! }.not_to raise_error
  end

  it 'recusa quem só tem meta_ads_view' do
    expect { operation_for(membership(%w[meta_ads_view])).authorize! }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'recusa o agente sem função' do
    expect { operation_for(membership).authorize! }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'segue deixando o administrador' do
    expect { operation_for(AccountUser.find_by(account: account, user: admin)).authorize! }.not_to raise_error
  end
end
