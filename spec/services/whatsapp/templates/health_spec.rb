require 'rails_helper'

RSpec.describe Whatsapp::Templates::Health do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:now) { Time.zone.parse('2026-10-20 12:00') }
  let(:boas_vindas) { { 'name' => 'boas_vindas', 'language' => 'pt_BR', 'category' => 'MARKETING' } }
  let(:aviso) { { 'name' => 'aviso', 'language' => 'pt_BR', 'category' => 'UTILITY' } }

  def health(templates = [boas_vindas, aviso], for_inbox: inbox)
    described_class.new(inbox: for_inbox, templates: templates, now: now).perform
  end

  def key(template)
    [template['name'], template['language'].downcase]
  end

  def conversation_in(target_inbox = inbox)
    create(:conversation, account: account, inbox: target_inbox)
  end

  def sent(template, conversation:, at: now - 1.day, status: :sent, language: template['language'])
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, status: status,
                     created_at: at, additional_attributes: { 'template_params' => { 'name' => template['name'], 'language' => language } })
  end

  def reply(conversation, at:)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, created_at: at)
  end

  describe 'messages sent in a conversation' do
    it 'counts sent, received, read and replied within 72 hours over the last 30 days' do
      read = conversation_in
      sent(boas_vindas, conversation: read, status: :read)
      reply(read, at: now - 1.day + 2.hours)
      late = conversation_in
      sent(boas_vindas, conversation: late, status: :delivered, at: now - 5.days)
      reply(late, at: now - 5.days + 80.hours)
      before = conversation_in
      reply(before, at: now - 3.days)
      sent(boas_vindas, conversation: before, at: now - 2.days)
      sent(boas_vindas, conversation: conversation_in, status: :failed)
      sent(boas_vindas, conversation: conversation_in, status: :read, at: now - 31.days)

      expect(health[key(boas_vindas)]).to include(days: 30, sent: 3, delivered: 2, read: 1, replied: 1)
    end

    it 'never counts more replies than deliveries: a reply to a send not delivered does not count' do
      conversation = conversation_in
      sent(boas_vindas, conversation: conversation, status: :sent)
      reply(conversation, at: now - 20.hours)

      expect(health[key(boas_vindas)]).to include(sent: 1, delivered: 0, replied: 0)
    end

    it 'matches the language whatever the case it was stored with' do
      sent(boas_vindas, conversation: conversation_in, status: :delivered, language: 'PT_BR')

      expect(health([boas_vindas.merge('language' => 'pt_BR')])[key(boas_vindas)]).to include(delivered: 1)
    end

    it 'ignores another account, even with the same WhatsApp account id' do
      other_account = create(:account)
      other = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false)
      other.update_columns(provider_config: other.provider_config.merge('business_account_id' => channel.waba_id)) # rubocop:disable Rails/SkipsModelValidations
      foreign = create(:conversation, account: other_account, inbox: other.inbox)
      create(:message, account: other_account, inbox: other.inbox, conversation: foreign, message_type: :outgoing, status: :read,
                       created_at: now - 1.day,
                       additional_attributes: { 'template_params' => { 'name' => 'boas_vindas', 'language' => 'pt_BR' } })

      expect(health[key(boas_vindas)]).to include(sent: 0)
    end

    it 'separates templates by name and language' do
      sent(boas_vindas, conversation: conversation_in, status: :delivered)
      sent(boas_vindas, conversation: conversation_in, status: :delivered, language: 'en')
      sent(aviso, conversation: conversation_in, status: :delivered)

      result = health
      expect(result[key(boas_vindas)]).to include(sent: 1, delivered: 1)
      expect(result[key(aviso)]).to include(sent: 1, delivered: 1)
    end

    it 'counts every inbox of the same WhatsApp account and no other account' do
      channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => 'waba_a')) # rubocop:disable Rails/SkipsModelValidations
      same = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      same.update_columns(provider_config: same.provider_config.merge('business_account_id' => 'waba_a')) # rubocop:disable Rails/SkipsModelValidations
      other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      other.update_columns(provider_config: other.provider_config.merge('business_account_id' => 'waba_b')) # rubocop:disable Rails/SkipsModelValidations
      sent(boas_vindas, conversation: conversation_in, status: :delivered)
      sent(boas_vindas, conversation: conversation_in(same.inbox), status: :delivered)
      sent(boas_vindas, conversation: conversation_in(other.inbox), status: :delivered)

      expect(health[key(boas_vindas)]).to include(sent: 2, delivered: 2)
    end
  end

  describe 'campaign sends' do
    let(:campaign) { create(:campaign, account: account, inbox: inbox, template_params: { 'name' => 'boas_vindas', 'language' => 'pt_BR' }) }

    def recipient(status, sent_at: now - 2.days)
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: create(:contact, account: account),
                                status: status, sent_at: sent_at)
    end

    it 'counts recipients accepted in the window and the contacts whose conversation got the campaign mark' do
      replied = recipient(:read)
      recipient(:delivered)
      not_delivered = recipient(:sent)
      recipient(:failed)
      recipient(:queued, sent_at: nil)
      recipient(:read, sent_at: now - 40.days)
      marked = create(:conversation, account: account, inbox: inbox, contact: replied.contact)
      marked.update!(additional_attributes: { 'campaign_source_ids' => [CampaignJourney::CampaignMarks.source_id_for(campaign)] })
      also_marked = create(:conversation, account: account, inbox: inbox, contact: not_delivered.contact)
      also_marked.update!(additional_attributes: { 'campaign_source_ids' => [CampaignJourney::CampaignMarks.source_id_for(campaign)] })

      expect(health[key(boas_vindas)]).to include(sent: 3, delivered: 2, read: 1, replied: 1)
    end
  end

  describe 'cost' do
    it 'prices what was delivered by the template category and divides it by the replies' do
      2.times do
        conversation = conversation_in
        sent(boas_vindas, conversation: conversation, status: :delivered)
        reply(conversation, at: now - 20.hours)
      end
      sent(boas_vindas, conversation: conversation_in, status: :sent)
      price = Whatsapp::Pricing.per_message('marketing')

      expect(health[key(boas_vindas)][:cost]).to eq(total: (price.amount * 2).to_f, per_reply: price.amount.to_f, currency: price.currency)
    end

    it 'has no cost per reply when nobody replied and no cost when nothing was sent' do
      sent(boas_vindas, conversation: conversation_in, status: :delivered)

      result = health
      expect(result[key(boas_vindas)][:cost]).to include(per_reply: nil)
      expect(result[key(aviso)]).to include(sent: 0, delivered: 0, read: 0, replied: 0, cost: nil)
    end

    it 'has no cost when the price table has no currency' do
      sent(boas_vindas, conversation: conversation_in, status: :delivered)
      price = Whatsapp::Pricing::Price.new(category: 'marketing', amount: BigDecimal('0.3'), currency: '', country: 'BR', effective_from: '')
      allow(Whatsapp::Pricing).to receive(:per_message).and_return(price)

      expect(health[key(boas_vindas)][:cost]).to be_nil
    end

    it 'has no cost when the category has no price' do
      sent(boas_vindas, conversation: conversation_in, status: :delivered)

      expect(health([boas_vindas.merge('category' => nil)])[key(boas_vindas)][:cost]).to be_nil
    end
  end

  describe 'average reply rate of the templates' do
    let(:pesquisa) { { 'name' => 'pesquisa', 'language' => 'pt_BR', 'category' => 'UTILITY' } }

    def deliveries(template, total, replied)
      total.times do |index|
        conversation = conversation_in
        sent(template, conversation: conversation, status: :delivered)
        reply(conversation, at: now - 20.hours) if index < replied
      end
    end

    it 'is shown only with at least 3 templates with deliveries' do
      deliveries(boas_vindas, 4, 1)
      deliveries(aviso, 2, 1)

      expect(health.values.pluck(:average_reply_rate).uniq).to eq([nil])
    end

    it 'is the reply rate of all deliveries of the templates, in whole percent' do
      deliveries(boas_vindas, 4, 1)
      deliveries(aviso, 2, 1)
      deliveries(pesquisa, 4, 2)

      expect(health([boas_vindas, aviso, pesquisa]).values.pluck(:average_reply_rate).uniq).to eq([40])
    end
  end
end
