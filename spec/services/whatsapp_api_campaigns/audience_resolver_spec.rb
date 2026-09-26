require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::AudienceResolver do
  it 'creates one durable recipient per labelled contact and stores masked phone only' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    create_labelled_contact(account: account, label: label, name: 'Sem Telefone', phone_number: nil)
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.count).to eq(2)
    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.first.phone_mask).not_to include('987654321')
    expect(campaign.reload.recipients_count).to eq(2)
  end

  it 'marks duplicate phones as failed so the campaign sends only once to a number' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    duplicate = create_labelled_contact(account: account, label: label, name: 'Ana Duplicada', phone_number: '+5511987654322')
    duplicate.update_columns(phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.count).to eq(1)
    expect(campaign.whatsapp_api_campaign_recipients.failed.first.last_error_message).to eq('duplicate_phone_number')
  end

  describe 'recusa de mensagens ativas (chat#737)' do
    it 'cancela na resolução o destinatário cujo contato recusou, sem contar como falha' do
      account, user, inbox, label = create_account_user_inbox_and_label
      create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
      recusou = create_labelled_contact(account: account, label: label, name: 'Bia Recusa', phone_number: '+5521987654321')
      recusou.opt_out!(source: 'manual')
      campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

      described_class.new(campaign).perform

      recipient = campaign.whatsapp_api_campaign_recipients.find_by(contact: recusou)
      expect(recipient).to be_cancelled
      expect(recipient.cancelled_at).to be_present
      expect(recipient.last_error_message).to eq('opted_out')
      expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
      expect(campaign.reload.failed_count).to eq(0)
      expect(campaign.cancelled_count).to eq(1)
      expect(campaign.opted_out_count).to eq(1)
    end

    it 'não deixa o telefone do recusado bloquear outro contato com o mesmo número' do
      account, user, inbox, label = create_account_user_inbox_and_label
      recusou = create_labelled_contact(account: account, label: label, name: 'Ana Recusa', phone_number: '+5511987654321')
      recusou.opt_out!(source: 'manual')
      outro = create_labelled_contact(account: account, label: label, name: 'Ana Outra', phone_number: '+5511987654322')
      outro.update_columns(phone_number: '+5511987654321')
      campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

      described_class.new(campaign).perform

      expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: recusou)).to be_cancelled
      expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: outro)).to be_pending
    end

    it 'não muda nada para quem não recusou' do
      account, user, inbox, label = create_account_user_inbox_and_label
      create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
      campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

      described_class.new(campaign).perform

      expect(campaign.whatsapp_api_campaign_recipients.pending.count).to eq(1)
      expect(campaign.reload.cancelled_count).to eq(0)
      expect(campaign.opted_out_count).to eq(0)
    end
  end
end
