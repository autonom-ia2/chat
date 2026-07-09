require 'rails_helper'

RSpec.describe Crm::FollowUps::TemplateCandidates do
  subject(:candidates) { described_class.new(conversation: conversation).perform }

  let(:account) { create(:account) }

  # TemplateCandidates only reads conversation.inbox -> channel; build a real
  # (persisted-inbox) conversation without going through ContactInboxBuilder,
  # whose Twilio source_id format validation is irrelevant to template resolution.
  def build_conversation(channel)
    Conversation.new(account: account, inbox: channel.inbox)
  end

  def twilio_template(overrides = {})
    {
      'content_sid' => "HX#{SecureRandom.hex(16)}",
      'friendly_name' => 'template',
      'language' => 'pt_BR',
      'status' => 'approved',
      'template_type' => 'text',
      'category' => 'marketing',
      'body' => 'Olá {{1}}',
      'variables' => { '1' => 'cliente' }
    }.merge(overrides.stringify_keys)
  end

  context 'when the Twilio channel is WhatsApp with approved templates' do
    let(:templates) do
      [
        twilio_template(friendly_name: 'reengage_promo', category: 'marketing', content_sid: 'HXmarketing1'),
        twilio_template(friendly_name: 'order_update', category: 'utility', content_sid: 'HXutility1'),
        twilio_template(friendly_name: 'login_code', category: 'authentication', content_sid: 'HXauth1'),
        twilio_template(friendly_name: 'pending_promo', status: 'pending', category: 'marketing', content_sid: 'HXpending1')
      ]
    end
    let(:channel) do
      create(:channel_twilio_sms, :whatsapp, account: account, content_templates: { 'templates' => templates })
    end
    let(:conversation) { build_conversation(channel) }

    it 'maps approved marketing and utility templates into twilio candidates' do
      names = candidates.map { |candidate| candidate[:name] }

      expect(names).to contain_exactly('reengage_promo', 'order_update')
    end

    it 'excludes non-approved templates even when the category is eligible' do
      expect(candidates.map { |candidate| candidate[:name] }).not_to include('pending_promo')
    end

    it 'excludes approved templates whose category is not marketing or utility' do
      expect(candidates.map { |candidate| candidate[:name] }).not_to include('login_code')
    end

    it 'exposes the fields the follow-up composer and Twilio send path need' do
      marketing = candidates.find { |candidate| candidate[:name] == 'reengage_promo' }

      expect(marketing).to include(
        kind: 'twilio',
        name: 'reengage_promo',
        id: 'HXmarketing1',
        content_sid: 'HXmarketing1',
        language: 'pt_BR',
        body: 'Olá {{1}}',
        variables: ['1'],
        category: 'marketing'
      )
    end
  end

  context 'when the Twilio channel medium is sms' do
    let(:sms_templates) { { 'templates' => [twilio_template(friendly_name: 'reengage_promo')] } }
    let(:channel) { create(:channel_twilio_sms, account: account, content_templates: sms_templates) }
    let(:conversation) { build_conversation(channel) }

    it 'returns no candidates because sms has no template window' do
      expect(candidates).to eq([])
    end
  end

  context 'when the Twilio WhatsApp channel has no synced templates' do
    let(:channel) { create(:channel_twilio_sms, :whatsapp, account: account, content_templates: nil) }
    let(:conversation) { build_conversation(channel) }

    it 'returns an empty array without raising' do
      expect(candidates).to eq([])
    end
  end
end
