require 'rails_helper'

# Perfil do modelo (#1330): um por caixa, nome e idioma; campos do catálogo como mapa de texto; caixa da mesma conta.
RSpec.describe WhatsappTemplateProfile do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }

  def build_profile(**attrs)
    described_class.new({ account: account, inbox: inbox, waba_id: channel.waba_id, name: 'boas_vindas', language: 'pt_BR' }.merge(attrs))
  end

  it 'não repete nome e idioma na mesma caixa' do
    build_profile.save!

    expect(build_profile).not_to be_valid
    expect(build_profile(language: 'en')).to be_valid
  end

  it 'campos são um mapa de variável para chave do catálogo' do
    expect(build_profile(fields: { '1' => 'cliente.primeiro_nome' })).to be_valid
    expect(build_profile(fields: { '1' => { 'x' => 1 } })).not_to be_valid
  end

  it 'a caixa precisa ser da conta' do
    expect(build_profile(account: create(:account))).not_to be_valid
  end

  it 'perfis da caixa são os da mesma conta e da mesma WABA' do
    mine = build_profile.tap(&:save!)
    other_account = create(:account)
    other_inbox = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false,
                                            validate_provider_config: false).inbox
    described_class.create!(account: other_account, inbox: other_inbox, waba_id: channel.waba_id, name: 'boas_vindas', language: 'pt_BR')

    expect(described_class.for_inbox(inbox)).to contain_exactly(mine)
  end
end
