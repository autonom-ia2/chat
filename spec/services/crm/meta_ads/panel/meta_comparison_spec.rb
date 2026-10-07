require 'rails_helper'

# "Quanto confiar", Meta × nós (#1110, F5): uma linha por destino marcado, até ontem, cada conversa pela origem do
# primeiro toque, só os toques da mesma conta de anúncios (ou sem conta).
RSpec.describe Crm::MetaAds::Panel::MetaComparison do
  let(:now) { Time.zone.parse('2026-10-07T15:00:00-03:00') }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:setup) { advisor_setup }
  let(:account) { setup.first }
  let(:connection) { setup.last }

  around { |example| travel_to(now) { example.run } }

  def comparison(days: 7)
    described_class.new(connection, Crm::MetaAds::Panel::Report.new(connection, days: days)).payload
  end

  # Um dia de gasto do anúncio A, com as conversas iniciadas e, em `actions`, os leads e as visitas do Pixel.
  def insight(date, spend: 10, conversations: 0, leads: 0, visits: 0)
    actions = [{ 'action_type' => 'offsite_conversion.fb_pixel_lead', 'value' => leads.to_s, '7d_click' => leads.to_s },
               { 'action_type' => 'landing_page_view', 'value' => visits.to_s, '7d_click' => visits.to_s },
               { 'action_type' => 'link_click', 'value' => '99', '7d_click' => '99' }]
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: 'A', date: date, currency: 'BRL',
                                    spend: spend, conversations_started: conversations, actions: actions, attribution_window: '7d_click',
                                    fetched_at: now)
  end

  def link_from(conversation, origin, day, hour: 12, ad_account_id: connection.ad_account_id)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: origin, certainty: 'ad',
                            ad_id: 'A', ad_account_id: ad_account_id, touched_at: zone.local(2026, 10, day, hour))
  end

  def conversations(count)
    create_list(:conversation, count, account: account)
  end

  it 'compara cada destino até ontem, pela origem do primeiro toque de cada conversa' do
    connection.update!(destinations: { 'whatsapp' => true, 'site' => true })
    insight(Date.new(2026, 10, 3), conversations: 10, leads: 4, visits: 9)
    insight(Date.new(2026, 10, 7), conversations: 50, leads: 50, visits: 50) # hoje: fora
    insight(Date.new(2026, 9, 30), conversations: 70, leads: 70)             # antes do período de 7 dias
    whatsapp, site_then_whatsapp, today, other_account, without_account = conversations(5)
    link_from(whatsapp, 'whatsapp', 2)
    link_from(site_then_whatsapp, 'site', 3)
    link_from(site_then_whatsapp, 'whatsapp', 4)
    link_from(today, 'whatsapp', 7, hour: 9)
    link_from(other_account, 'whatsapp', 5, ad_account_id: '777')
    link_from(without_account, 'site', 4, ad_account_id: nil)

    expect(comparison).to eq(
      days: 7, until: Date.new(2026, 10, 6), explanation: nil,
      rows: [
        { destination: 'whatsapp', meta: 10, ours: 1, difference: -9, explanation: 'meta_higher' },
        { destination: 'site', meta: 4, meta_visits: 9, ours: 2, difference: -2, explanation: 'close' }
      ]
    )
  end

  it 'perto é até 2 ou 10% do número da Meta; acima, diz quem contou mais' do
    insight(Date.new(2026, 10, 1), conversations: 40)
    conversations(45).each { |conversation| link_from(conversation, 'whatsapp', 2) }

    expect(comparison[:rows].sole).to include(meta: 40, ours: 45, difference: 5, explanation: 'ours_higher')

    conversations(1).each { |conversation| link_from(conversation, 'whatsapp', 2) }
    insight(Date.new(2026, 10, 2), conversations: 2)

    expect(comparison[:rows].sole).to include(meta: 42, ours: 46, difference: 4, explanation: 'close')
  end

  it 'destino não marcado não tem linha, mesmo com número da Meta' do
    insight(Date.new(2026, 10, 3), conversations: 5, leads: 8, visits: 20)
    link_from(conversations(1).first, 'site', 3)

    expect(comparison[:rows].map { |row| row[:destination] }).to eq(['whatsapp'])
  end

  it 'sem número da Meta e sem conversa nossa, nil; com gasto e só a nossa conta, no_meta_data' do
    connection.update!(destinations: { 'whatsapp' => true, 'site' => true })
    insight(Date.new(2026, 10, 3), spend: 50)

    expect(comparison).to be_nil

    link_from(conversations(1).first, 'site', 3)

    expect(comparison).to include(explanation: 'no_meta_data',
                                  rows: [{ destination: 'site', meta: 0, meta_visits: 0, ours: 1, difference: 1, explanation: 'close' }])
  end

  it 'segue o período do painel' do
    insight(Date.new(2026, 9, 20), conversations: 12)
    conversations(12).each { |conversation| link_from(conversation, 'whatsapp', 1) }

    expect(comparison(days: 30)).to include(days: 30, rows: [include(meta: 12, ours: 12, explanation: 'close')])
    expect(comparison(days: 7)[:rows].sole).to include(meta: 0, ours: 12)
  end
end
