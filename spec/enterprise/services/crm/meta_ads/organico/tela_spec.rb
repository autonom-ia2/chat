require 'rails_helper'

# Seus posts (#2199) com função personalizada (parecer da sessão Funções, 27/10). A contagem de conversas é só das que a
# pessoa vê, e o id e o nome da caixa vão só para quem vê a caixa ou pode reautorizá-la (integration_manage). Fica em
# spec/enterprise: a metade de função personalizada do permission_granted? e do filtro de conversas é EE. A leitura da
# Meta é substituída: aqui só importa o que a tela acrescenta por pessoa.
RSpec.describe Crm::MetaAds::Organico::Tela do
  let(:account) { create(:account) }
  let(:channel) do
    stub_request(:post, 'https://graph.facebook.com/v3.2/me/subscribed_apps')
    create(:channel_facebook_page, account: account, page_id: '1001', inbox: nil)
  end
  let!(:inbox) { create(:inbox, account: account, channel: channel, name: 'Studio Acme') }

  before do
    Rails.cache.clear
    Current.account = account
  end

  after { Current.reset }

  def member_with(permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def page_for(user, meta)
    Current.user = user
    allow(Crm::MetaAds::Organico::Pagina).to receive(:new).and_return(instance_double(Crm::MetaAds::Organico::Pagina, perform: meta))
    viewer = { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
    described_class.new(account: account, days: 30, viewer: viewer).perform[:page]
  end

  it 'integration_manage sem ver a caixa recebe o id para reautorizar, mas não a contagem' do
    page = page_for(member_with(%w[integration_manage]), { status: 'ok', name: 'Studio Acme' })

    expect(page[:messages]).to eq(count: nil, inbox_id: inbox.id)
  end

  it 'integration_manage sem ver a caixa recebe o nome da caixa no "Libere sua Página"' do
    page = page_for(member_with(%w[integration_manage]), { status: 'needs_permission', name: 'Studio Acme' })

    expect(page).to eq(status: 'needs_permission', name: 'Studio Acme', inbox_id: inbox.id)
  end

  it 'conta só as conversas que a função alcança, não todas as da caixa' do
    agente = member_with(%w[conversation_participating_manage])
    create(:inbox_member, user: agente, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: agente)
    create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent))

    page = page_for(agente, { status: 'ok', name: 'Studio Acme' })

    expect(page[:messages]).to eq(count: 1, inbox_id: inbox.id)
  end
end
