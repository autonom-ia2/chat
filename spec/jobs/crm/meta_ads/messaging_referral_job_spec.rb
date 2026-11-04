require 'rails_helper'

# Evento só de referral (#2521): o anúncio vai para a conversa mais recente do contato em cada caixa da Página.
RSpec.describe Crm::MetaAds::MessagingReferralJob do
  let(:referral) { { 'source' => 'ADS', 'ad_id' => '120200000000000001' } }

  def conversation_in(inbox, source_id)
    contact_inbox = create(:contact_inbox, inbox: inbox, source_id: source_id)
    create(:conversation, account: inbox.account, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
  end

  it 'Messenger: grava em toda caixa da mesma Página, com o id do evento pelo remetente e a hora' do
    first = create(:channel_facebook_page, page_id: 'page-1')
    second = create(:channel_facebook_page, page_id: 'page-1', account: create(:account))
    conversations = [first, second].map { |page| conversation_in(page.inbox, 'psid-1') }

    described_class.perform_now('messenger', 'page-1', 'psid-1', referral, '1700000000')

    conversations.each do |conversation|
      expect(conversation.reload.additional_attributes['campaign_touches'].sole)
        .to include('source' => 'meta_ctm', 'referral_id' => 'psid-1:1700000000')
    end
  end

  it 'Instagram: acha a caixa pelo id da conta; caixa desconhecida não faz nada' do
    channel = create(:channel_instagram, instagram_id: 'ig-business-1')
    conversation = conversation_in(channel.inbox, 'igsid-1')

    described_class.perform_now('instagram', 'ig-business-1', 'igsid-1', referral, '1700000000')
    described_class.perform_now('instagram', 'ig-desconhecido', 'igsid-1', referral, '1700000001')

    expect(conversation.reload.additional_attributes['campaign_touches'].sole).to include('source' => 'meta_ctd')
  end

  it 'sem a hora do evento não grava (todo clique do contato teria o mesmo id)' do
    page = create(:channel_facebook_page, page_id: 'page-1')
    conversation = conversation_in(page.inbox, 'psid-1')

    described_class.perform_now('messenger', 'page-1', 'psid-1', referral, '')

    expect(conversation.reload.additional_attributes).not_to have_key('campaign_touches')
  end
end
