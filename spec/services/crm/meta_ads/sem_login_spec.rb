require 'rails_helper'

# Anúncios sem login (#1960): quando a página usa o resultado do WhatsApp e o que a tela vazia recebe.
RSpec.describe Crm::MetaAds::SemLogin do
  let(:account) { create(:account) }
  let(:admin) { AccountUser.find_by(account: account, user: create(:user, account: account, role: :administrator)) }

  before { account.enable_features!('anuncios_sem_login') }

  def official_whatsapp(target = account, phone = '+5511988887777')
    create(:channel_whatsapp, account: target, phone_number: phone, sync_templates: false, validate_provider_config: false)
  end

  it 'vale com a flag e WhatsApp oficial enquanto não há conexão ativa com conta de anúncios (#2054)' do
    official_whatsapp
    expect(described_class.whatsapp_panel?(account)).to be(true)
    expect(described_class.payload(account, admin)).to include(enabled: true, connection_state: nil, connection_mode: nil)

    connection = create_meta_ads_connection(account).tap { |row| row.update!(mode: 'facebook_login') }
    expect(described_class.payload(account, admin)).to include(enabled: true, connection_state: 'choosing', connection_mode: 'facebook_login')

    connection.update!(ad_account_id: '999', status: 'invalid')
    expect(described_class.payload(account, admin)).to include(enabled: true, connection_state: 'broken')

    connection.update!(status: 'active')
    expect(described_class.whatsapp_panel?(account)).to be(false)
    expect(described_class.payload(account, admin)).to eq(enabled: false)
  end

  it 'não vale sem WhatsApp oficial: a conta segue com a tela de sempre' do
    create(:inbox, account: account)

    expect(described_class.whatsapp_panel?(account)).to be(false)
    expect(described_class.payload(account, admin)).to eq(enabled: false)
  end

  it 'não vale sem a flag' do
    official_whatsapp
    account.disable_features!('anuncios_sem_login')

    expect(described_class.whatsapp_panel?(account)).to be(false)
  end

  it 'lista as caixas de WhatsApp oficial da conta que a pessoa acessa (administrador, todas) e diz se houve anúncio nos últimos 90 dias' do
    mine = official_whatsapp
    official_whatsapp(create(:account), '+5511900000000')
    create(:inbox, account: account)

    expect(described_class.payload(account, admin)).to include(
      enabled: true, ad_touch: false, official_inboxes: [{ id: mine.inbox.id, name: mine.inbox.name, phone: '+5511988887777' }]
    )

    agente = create(:user, account: account, role: :agent)
    sem_caixa = AccountUser.find_by(account: account, user: agente)
    expect(described_class.payload(account, sem_caixa)).to include(enabled: true, official_inboxes: [])
    mine.inbox.add_members([agente.id])
    expect(described_class.payload(account, sem_caixa)[:official_inboxes].pluck(:id)).to eq([mine.inbox.id])

    # Anúncio antigo também conta (#2011): quem anunciou há meses vê o painel com o histórico, não a tela "pronto".
    click = { 'source' => 'meta_ctwa', 'source_id' => '120254710362980416', 'touched_at' => 200.days.ago.utc.iso8601 }
    conversation = create(:conversation, account: account)
    conversation.update_columns(additional_attributes: { 'campaign_touches' => [click] }, updated_at: 200.days.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.ad_touch?(account)).to be(true)
  end
end
