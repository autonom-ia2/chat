require 'rails_helper'

# #2211 — "por onde mandar" para começar conversa vem do Contacts::ContactableInboxesService. Contato sem telefone não
# recebe por nenhum tipo de WhatsApp, inclusive a caixa API ligada ao WAHA (o WhatsApp pelo celular).
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

  it 'telefone em branco conta como sem telefone' do
    em_branco = create(:contact, account: account, email: 'em.branco@example.com', phone_number: '')
    expect(caixas_de(em_branco)).not_to include(celular.id)
  end
end
