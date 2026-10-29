require 'rails_helper'

# #1705: front and back read the same examples (spec/fixtures/whatsapp_templates/formatos_da_conversa.json, real Meta
# format). The front side is app/javascript/dashboard/components-next/whatsapp/specs/formatosDaConversa.spec.js. A rule
# changed on one side alone fails one of the two. #1716: product and carousel go out when the send is complete (the
# products chosen, the cards with their photos) and are refused only when incomplete; products need the
# whatsapp_campaign_products flag, as in the campaign.
RSpec.describe Whatsapp::Templates::ConversationSendGuard do
  fixture = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_templates/formatos_da_conversa.json').read)

  let(:now) { Time.zone.at(fixture['agora_ms'] / 1000) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: fixture['casos'].map { |caso| caso['template'] }.uniq)
  end
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }
  let(:meta_url) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }
  let(:sent) { [] }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:graph) { "https://graph.facebook.com/#{Whatsapp::Templates::MetaClient.api_version}" }

  before do
    channel.inbox.account.enable_features!('whatsapp_campaign_products')
    stub_request(:post, meta_url).to_return do |request|
      sent << JSON.parse(request.body).dig('template', 'components')
      { status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: json }
    end
    stub_catalog
    stub_meta_media_upload # #2367: the carousel photos go up to Meta and the cards carry their ids
  end

  # The catalog of the inbox WABA, read again on each product send (Whatsapp::Templates::DispatchProducts).
  def stub_catalog
    catalogs = { data: [{ 'id' => 'cat-1', 'name' => 'Loja' }] }.to_json
    stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs")
      .with(query: hash_including({}))
      .to_return(status: 200, headers: json, body: catalogs)
    rows = %w[sku-1 sku-2].map { |id| { 'retailer_id' => id, 'name' => id, 'price' => 'R$ 10', 'availability' => 'in stock' } }
    stub_request(:get, "#{graph}/cat-1/products")
      .with(query: hash_including({}))
      .to_return(status: 200, headers: json, body: { data: rows }.to_json)
  end

  # FOTO_n in the fixture = the file the screen chose for the card: a photo of this account.
  def with_photos(processed)
    cards = processed.dig('carousel', 'cards')
    return processed unless cards

    processed.merge('carousel' => { 'cards' => cards.map { |card| card.merge('header' => { 'media_blob' => photo.signed_id }) } })
  end

  def photo
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'foto.png', content_type: 'image/png',
                                           metadata: { 'account_id' => channel.inbox.account_id })
  end

  def send_template(caso)
    template = caso['template']
    message = create(:message, message_type: :outgoing, conversation: conversation, account: conversation.account,
                               inbox: channel.inbox,
                               additional_attributes: { template_params: { name: template['name'], language: template['language'],
                                                                           category: template['category'],
                                                                           processed_params: with_photos(caso['processed_params']) } })
    travel_to(now) { Whatsapp::SendOnWhatsappService.new(message: message).perform }
    message.reload
  end

  it 'the conversation offers a template only when its send can go out (front ready <=> back sendable)' do
    fixture['casos'].select { |caso| caso['conversa'] }.each do |caso|
      expect(caso['pronto']).to eq(caso['envio'].nil?), caso['nome']
    end
  end

  fixture['casos'].each do |caso|
    describe caso['nome'] do
      it "SendableFormat says #{caso['envio'] || 'sendable'}" do
        result = Whatsapp::Templates::SendableFormat.check(caso['template'], recorded: caso['processed_params'], now: now, url_suffix: true)

        expect(result.reason_code).to eq(caso['envio'])
      end

      it "the conversation send #{caso['guarda'] ? "fails with #{caso['guarda']}" : 'goes to Meta'}" do
        message = send_template(caso)

        if caso['guarda']
          expect(message).to have_attributes(status: 'failed',
                                             external_error: I18n.t("whatsapp_templates.errors.#{caso['guarda']}"))
          expect(a_request(:post, meta_url)).not_to have_been_made
        else
          expect(message).to have_attributes(source_id: 'wamid.1', external_error: nil)
        end
      end

      next unless caso['guarda_sem_a_flag']

      it "without the products flag the complete send fails with #{caso['guarda_sem_a_flag']}" do
        channel.inbox.account.disable_features!('whatsapp_campaign_products')
        message = send_template(caso)

        expect(message).to have_attributes(status: 'failed',
                                           external_error: I18n.t("whatsapp_templates.errors.#{caso['guarda_sem_a_flag']}"))
        expect(a_request(:post, meta_url)).not_to have_been_made
      end
    end
  end

  it 'the offer with its validity reaches Meta in the official format' do
    message = send_template(fixture['casos'].find { |caso| caso['nome'] == 'oferta_com_validade_preenchida' })

    expect(message.external_error).to be_nil
    expect(sent.last).to include(
      { 'type' => 'limited_time_offer',
        'parameters' => [{ 'type' => 'limited_time_offer', 'limited_time_offer' => { 'expiration_time_ms' => 1_792_238_400_000 } }] },
      { 'type' => 'button', 'sub_type' => 'copy_code', 'index' => 0,
        'parameters' => [{ 'type' => 'coupon_code', 'coupon_code' => 'HOJE25' }] }
    )
  end
end
