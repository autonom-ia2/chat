require 'rails_helper'

# #2211 — "por onde mandar" para começar conversa vem do Contacts::ContactableInboxesService. Contato sem telefone não
# recebe por nenhum tipo de WhatsApp, inclusive a caixa API ligada ao WAHA (o WhatsApp pelo celular) — salvo quando a
# WAHA já sabe o chat dele (LID).
RSpec.describe Waha::CaixaDoCelularSoComTelefone do
  let(:account) { create(:account) }
  # As fábricas dos canais API e e-mail já criam a caixa.
  let(:celular) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox }
  let(:api_comum) { create(:channel_api, account: account).inbox }
  let(:email) { create(:channel_email, account: account).inbox }
  let(:whatsapp_oficial) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:twilio_whatsapp) { create(:inbox, account: account, channel: create(:channel_twilio_sms, medium: :whatsapp, account: account)) }

  before { [celular, api_comum, email, whatsapp_oficial, twilio_whatsapp] }

  def caixas_de(contato)
    Contacts::ContactableInboxesService.new(contact: contato).get.map { |caixa| caixa[:inbox].id }
  end

  it 'contato só com e-mail: nenhuma caixa de WhatsApp, só o e-mail e a API comum' do
    so_email = create(:contact, account: account, email: 'so.email@example.com', phone_number: nil)
    expect(caixas_de(so_email)).to contain_exactly(email.id, api_comum.id)
  end

  it 'contato com telefone recebe também pelo WhatsApp do celular' do
    com_telefone = create(:contact, account: account, email: 'com.telefone@example.com', phone_number: '+5511978622068')
    expect(caixas_de(com_telefone)).to include(celular.id, whatsapp_oficial.id, twilio_whatsapp.id, email.id, api_comum.id)
  end

  it 'contato que chegou só com LID mantém o WhatsApp do celular: a WAHA manda pelo chat id' do
    so_lid = create(:contact, account: account, phone_number: nil,
                              custom_attributes: { 'waha_whatsapp_chat_id' => '123456789012345@lid', 'waha_whatsapp_lid' => '123456789012345@lid' })
    expect(caixas_de(so_lid)).to include(celular.id)
    expect(caixas_de(so_lid)).not_to include(whatsapp_oficial.id, twilio_whatsapp.id)
  end

  it 'vínculo com chat id do WhatsApp no source_id também vale; com UUID, não' do
    pelo_vinculo = create(:contact, account: account, phone_number: nil)
    create(:contact_inbox, contact: pelo_vinculo, inbox: celular, source_id: '123456789012345@lid')
    expect(caixas_de(pelo_vinculo)).to include(celular.id)

    com_uuid = create(:contact, account: account, phone_number: nil, email: 'uuid@example.com')
    create(:contact_inbox, contact: com_uuid, inbox: celular, source_id: SecureRandom.uuid)
    expect(caixas_de(com_uuid)).not_to include(celular.id)
  end

  it 'telefone em branco conta como sem telefone' do
    em_branco = create(:contact, account: account, email: 'em.branco@example.com', phone_number: '')
    expect(caixas_de(em_branco)).not_to include(celular.id)
  end
end
