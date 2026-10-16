require 'rails_helper'

# #1703: a conversation (panel or API) sending a template that needs what only the campaign builds (catalog products,
# carousel cards) fails with the reason, without calling Meta. Real Meta format: HEADER format PRODUCT + SPM, MPM,
# CATALOG button, CAROUSEL (developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/
# {spm,mpm,product-card-carousel,catalog-template}-messages). Every other template keeps the Chatwoot path.
RSpec.describe Whatsapp::Templates::ConversationSendGuard do
  let(:body) { { 'type' => 'BODY', 'text' => 'Oi {{1}}' } }
  let(:normal) { approved('boas_vindas', body) }
  let(:one_product) do
    approved('produto_unico', { 'type' => 'HEADER', 'format' => 'PRODUCT' }, body,
             { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] })
  end
  let(:many_products) { approved('lista_de_produtos', body, buttons('MPM')) }
  let(:catalog_button) { approved('catalogo', body, buttons('CATALOG')) }
  let(:media_carousel) do
    card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Cartão' }] }
    approved('carrossel_de_fotos', body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
  end
  let(:coupon) { approved('cupom', body, buttons('COPY_CODE')) }
  let(:otp) { approved('codigo', { 'type' => 'BODY', 'text' => '{{1}} é o seu código.' }, buttons('OTP')) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [normal, one_product, many_products, catalog_button, media_carousel,
                                                  coupon, otp])
  end
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }
  let(:sent) { [] }
  let(:meta_url) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'parameter_format' => 'POSITIONAL', 'components' => components }
  end

  def buttons(type)
    { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => type, 'text' => 'Botão' }] }
  end

  def template_message(template, processed = { 'body' => { '1' => 'Ana' } })
    create(:message, message_type: :outgoing, conversation: conversation, account: conversation.account, inbox: channel.inbox,
                     additional_attributes: { template_params: { name: template['name'], language: 'pt_BR',
                                                                 category: 'MARKETING', processed_params: processed } })
  end

  def send_message(message)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  def stub_meta
    stub_request(:post, meta_url).to_return do |request|
      sent << JSON.parse(request.body).dig('template', 'components')
      { status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'is prepended into the Chatwoot send service by the initializer' do
    expect(Whatsapp::SendOnWhatsappService.ancestors).to include(described_class)
  end

  describe 'refused without calling Meta' do
    {
      'one product (PRODUCT header + SPM) without retailer_ids' => [:one_product, 'conversation_products'],
      'many products (MPM) without retailer_ids' => [:many_products, 'conversation_products'],
      'catalog button the conversation never fills' => [:catalog_button, 'conversation_products'],
      'carousel without its cards' => [:media_carousel, 'conversation_carousel']
    }.each do |label, (template, text)|
      it label do
        message = send_message(template_message(public_send(template)))

        expect(message).to have_attributes(status: 'failed', external_error: I18n.t("whatsapp_templates.errors.#{text}"))
        expect(a_request(:post, meta_url)).not_to have_been_made
      end
    end
  end

  describe 'sent as before' do
    before { stub_meta }

    it 'a normal template' do
      message = send_message(template_message(normal))

      expect(message).to have_attributes(source_id: 'wamid.1', external_error: nil)
      expect(sent.last).to eq([{ 'type' => 'body', 'parameters' => [{ 'type' => 'text', 'text' => 'Ana' }] }])
    end

    it 'a product template when the send carries the products (API caller)' do
      message = send_message(template_message(one_product, { 'body' => { '1' => 'Ana' },
                                                             'products' => { 'retailer_ids' => ['sku-1'] } }))

      expect(message.external_error).to be_nil
      expect(sent.last.first).to eq(
        'type' => 'header', 'parameters' => [{ 'type' => 'product', 'product' => { 'product_retailer_id' => 'sku-1' } }]
      )
    end

    it 'a coupon with its code, as the composer sends it' do
      message = send_message(template_message(coupon, { 'body' => { '1' => 'Ana' },
                                                        'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'CUPOM10' }] }))

      expect(message.external_error).to be_nil
      expect(sent.last.last).to include('sub_type' => 'copy_code', 'index' => 0)
    end

    it 'a verification code with its parameter (API caller): not this guard business' do
      message = send_message(template_message(otp, { 'body' => { '1' => '123456' },
                                                     'buttons' => [{ 'type' => 'otp', 'parameter' => '123456' }] }))

      expect(message.external_error).to be_nil
      expect(a_request(:post, meta_url)).to have_been_made.once
    end

    it 'a template outside the inbox list (Chatwoot path, unchanged)' do
      message = send_message(template_message(approved('nao_existe', body)))

      expect(message.external_error).to be_nil
      expect(a_request(:post, meta_url)).to have_been_made.once
    end
  end
end
