require 'rails_helper'

# #1705: front and back read the same examples (spec/fixtures/whatsapp_templates/formatos_da_conversa.json, real Meta
# format). The front side is app/javascript/dashboard/components-next/whatsapp/specs/formatosDaConversa.spec.js. A rule
# changed on one side alone fails one of the two.
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

  before do
    stub_request(:post, meta_url).to_return do |request|
      sent << JSON.parse(request.body).dig('template', 'components')
      { status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def send_template(caso)
    template = caso['template']
    message = create(:message, message_type: :outgoing, conversation: conversation, account: conversation.account,
                               inbox: channel.inbox,
                               additional_attributes: { template_params: { name: template['name'], language: template['language'],
                                                                           category: template['category'],
                                                                           processed_params: caso['processed_params'] } })
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
