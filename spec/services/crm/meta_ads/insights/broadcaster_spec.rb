require 'rails_helper'

# #2070: o aviso de leitura nova vai para quem vê Anúncios da Meta. Fora das funções personalizadas (o que o OSS
# conhece), isso é só o administrador: o agente comum e o membro oculto dos tokens de integração ficam de fora.
#
# A suíte sempre carrega o enterprise/ (o fork roda em modo Enterprise e o CI "Testes do fork" não remove a pasta),
# e o Enterprise::AccountUser entra por prepend na carga, sem como desfazer num exemplo. Por isso o OSS é coberto
# pelo equivalente: sem função personalizada, só o administrador recebe; e, sem a associação custom_role (como no
# OSS), a busca não tenta carregá-la e o administrador continua recebendo. As funções ficam no spec de spec/enterprise.
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

  it 'sem a associação custom_role, como no OSS, não a carrega e segue avisando o administrador' do
    connection
    allow(AccountUser).to receive(:reflect_on_association).and_call_original
    allow(AccountUser).to receive(:reflect_on_association).with(:custom_role).and_return(nil)

    described_class.broadcast(connection)

    expect(ActionCableBroadcastJob).to have_received(:perform_later).with([admin.pubsub_token], anything, anything)
  end
end
