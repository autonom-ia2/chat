require 'rails_helper'

# #2070: o aviso de leitura nova vai para quem vê Anúncios da Meta. Fora das funções personalizadas (o que o OSS
# conhece), isso é só o administrador: o agente comum e o membro oculto dos tokens de integração ficam de fora.
#
# A suíte sempre carrega o enterprise/ (o fork roda em modo Enterprise e o CI "Testes do fork" não remove a pasta),
# e o Enterprise::AccountUser entra por prepend na carga, sem como desfazer num exemplo. Por isso o OSS é coberto
# pelo equivalente: sem função personalizada, só o administrador recebe. O desvio da associação custom_role (que não
# existe no OSS) não tem como ser exercitado aqui; fica sem teste. As funções ficam no spec de spec/enterprise.
RSpec.describe Crm::MetaAds::Insights::Broadcaster do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:plain_agent) { create(:user, account: account, role: :agent) }
  let(:integration_member) do
    user = create(:user)
    AccountUser.create!(account: account, user: user, role: :administrator, integration: true)
    user
  end

  before do
    plain_agent
    integration_member
    allow(Crm::MetaAds::Insights::Summary).to receive(:payload).and_return({ spend: 1 })
    allow(ActionCableBroadcastJob).to receive(:perform_later)
  end

  it 'avisa só o administrador: nem o agente comum nem o membro oculto da integração' do
    described_class.broadcast(connection)

    expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, event, payload|
      expect(tokens).to eq([admin.pubsub_token])
      expect(tokens).not_to include(plain_agent.pubsub_token, integration_member.pubsub_token)
      expect(event).to eq(Events::Types::CRM_META_ADS_INSIGHTS_UPDATED)
      expect(payload).to include(account_id: account.id)
    end
  end
end
