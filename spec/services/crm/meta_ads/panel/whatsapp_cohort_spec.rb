require 'rails_helper'

# A coorte do painel sem conexão (#1960) lê os toques gravados na conversa com as regras da coorte das ligações.
RSpec.describe Crm::MetaAds::Panel::WhatsappCohort do
  let(:account) { create(:account) }
  let(:ad_id) { '120254710362980416' }
  let(:now) { Time.zone.parse('2026-10-20T15:00:00-03:00') }
  let(:range) { 30.days.ago(now)..now }

  def ad_click(at, source_id: ad_id)
    { 'source' => 'meta_ctwa', 'source_id' => source_id, 'source_type' => 'ad', 'touched_at' => at.utc.iso8601 }
  end

  def conversation_with(attrs, account: self.account, created_at: now - 1.day)
    conversation = create(:conversation, account: account)
    conversation.update_columns(additional_attributes: attrs, created_at: created_at, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  it 'conta o primeiro toque com anúncio do período, o toque de site com sinal da Meta e a origem antiga sem lista' do
    travel_to(now) do
      with_ad = conversation_with({ 'campaign_touches' => [ad_click(40.days.ago), ad_click(2.days.ago), ad_click(1.day.ago, source_id: '999')] })
      site = conversation_with({ 'campaign_touches' => [{ 'source' => 'link', 'source_id' => 'site:abc', 'fbclid' => 'x',
                                                          'touched_at' => 3.days.ago.utc.iso8601 }] })
      legacy = conversation_with({ 'campaign' => ad_click(5.days.ago).except('touched_at').merge('body' => 'texto longo') },
                                 created_at: 5.days.ago)
      conversation_with({ 'campaign_touches' => [{ 'source' => 'meta_organic', 'source_id' => 'post', 'touched_at' => 1.day.ago.utc.iso8601 }] })
      conversation_with({ 'campaign_touches' => [ad_click(1.day.ago)] }, account: create(:account))

      touches = described_class.new(account.id, range).touches

      expect(touches.keys).to contain_exactly(with_ad.id, site.id, legacy.id)
      expect(touches[with_ad.id]).to eq([ad_id, Time.zone.parse(2.days.ago.utc.iso8601)])
      expect(touches[site.id].first).to be_nil
      expect(touches[legacy.id].first).to eq(ad_id)
    end
  end

  it 'dá os mesmos números da coorte das ligações para o mesmo dado' do
    travel_to(now) do
      conversation = conversation_with({ 'campaign_touches' => [ad_click(2.days.ago)] })
      Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: 'k', origin: 'whatsapp', certainty: 'ad',
                              ad_id: ad_id, touched_at: Time.zone.parse(2.days.ago.utc.iso8601))

      expect(described_class.new(account.id, range).touches).to eq(Crm::MetaAds::Panel::Cohort.new(account.id, range).touches)
    end
  end

  it 'diz se houve toque de anúncio no período sem contar post orgânico nem toque fora do período' do
    travel_to(now) do
      conversation_with({ 'campaign_touches' => [{ 'source' => 'meta_organic', 'source_id' => 'post', 'touched_at' => 1.day.ago.utc.iso8601 }] })
      conversation_with({ 'campaign_touches' => [ad_click(40.days.ago)] })
      expect(described_class.new(account.id, range).any?).to be(false)

      conversation_with({ 'campaign_touches' => [ad_click(1.day.ago)] })
      expect(described_class.new(account.id, range).any?).to be(true)
    end
  end
end
