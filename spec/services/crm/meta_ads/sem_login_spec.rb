require 'rails_helper'

# Anúncios sem login (#1960): quando a página usa o resultado do WhatsApp e o que a tela vazia recebe.
RSpec.describe Crm::MetaAds::SemLogin do
  let(:account) { create(:account) }

  before { account.enable_features!('anuncios_sem_login') }

  def official_whatsapp(target = account, phone = '+5511988887777')
    create(:channel_whatsapp, account: target, phone_number: phone, sync_templates: false, validate_provider_config: false)
  end

  it 'vale só com a flag, WhatsApp oficial e sem conexão nenhuma, mesmo caída ou sem conta escolhida' do
    official_whatsapp
    expect(described_class.whatsapp_panel?(account)).to be(true)

    Crm::MetaAdsConnection.create!(account: account, mode: 'partner', status: 'invalid')
    expect(described_class.whatsapp_panel?(account)).to be(false)
    expect(described_class.payload(account)).to eq(enabled: false)
  end

  it 'não vale sem WhatsApp oficial: a conta segue com a tela de sempre' do
    create(:inbox, account: account)

    expect(described_class.whatsapp_panel?(account)).to be(false)
    expect(described_class.payload(account)).to eq(enabled: false)
  end

  it 'não vale sem a flag' do
    official_whatsapp
    account.disable_features!('anuncios_sem_login')

    expect(described_class.whatsapp_panel?(account)).to be(false)
  end

  it 'lista só as caixas de WhatsApp oficial da conta e diz se houve anúncio nos últimos 90 dias' do
    mine = official_whatsapp
    official_whatsapp(create(:account), '+5511900000000')
    create(:inbox, account: account)

    expect(described_class.payload(account)).to include(enabled: true, recent_ad_touch: false,
                                                        official_inboxes: [{ id: mine.inbox.id, name: mine.inbox.name, phone: '+5511988887777' }])

    click = { 'source' => 'meta_ctwa', 'source_id' => '120254710362980416', 'touched_at' => 10.days.ago.utc.iso8601 }
    create(:conversation, account: account).update_columns(additional_attributes: { 'campaign_touches' => [click] }) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.recent_ad_touch?(account)).to be(true)
  end
end
