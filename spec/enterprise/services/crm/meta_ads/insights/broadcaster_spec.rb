require 'rails_helper'

# #2070: o aviso de leitura nova vai para quem vê Anúncios da Meta — administrador ou função com meta_ads_view ou
# meta_ads_manage —, nunca para o agente comum nem para o membro oculto dos tokens de integração. EE: a metade de
# função personalizada do permission_granted? só existe aqui.
RSpec.describe Crm::MetaAds::Insights::Broadcaster do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:connection) { create_meta_ads_insights_connection(account) }

  def member_with(permissions)
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account: account, user: user).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  before do
    allow(Crm::MetaAds::Insights::Summary).to receive(:payload).and_return({ spend: 1 })
    allow(ActionCableBroadcastJob).to receive(:perform_later)
  end

  it 'avisa administrador, meta_ads_view e meta_ads_manage, e mais ninguém', :aggregate_failures do
    viewer = member_with(%w[meta_ads_view])
    manager = member_with(%w[meta_ads_manage])
    other_role = member_with(%w[crm_view])
    plain_agent = create(:user, account: account, role: :agent)

    described_class.broadcast(connection)

    expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, event, payload|
      expect(tokens).to contain_exactly(admin.pubsub_token, viewer.pubsub_token, manager.pubsub_token)
      expect(tokens).not_to include(other_role.pubsub_token, plain_agent.pubsub_token)
      expect(event).to eq(Events::Types::CRM_META_ADS_INSIGHTS_UPDATED)
      expect(payload).to include(account_id: account.id, spend: 1)
    end
  end

  it 'não lê a função de cada pessoa uma a uma' do
    3.times { member_with(%w[meta_ads_view]) }
    connection

    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql].include?('custom_roles') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { described_class.broadcast(connection) }

    expect(queries).to eq(1)
  end
end
