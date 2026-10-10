require 'rails_helper'

# Tempo de resposta das conversas de anúncio (#1110, F5, D5.6): qualquer resposta de verdade, mediana, a partir
# do primeiro toque, numa consulta só.
RSpec.describe Crm::MetaAds::Panel::ResponseTime do
  around do |example|
    travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) { example.run }
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:range) { 30.days.ago..Time.current }

  def conversation_at(at, touches: [at])
    conversation = create(:conversation, account: account, inbox: inbox)
    touches.each do |touched_at|
      Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                              certainty: 'ad', ad_id: '1', touched_at: touched_at)
    end
    message(conversation, :incoming, at)
    conversation
  end

  def message(conversation, type, at, **attributes)
    conversation.messages.create!(account: account, inbox: inbox, message_type: type, content: 'Oi', created_at: at, **attributes)
  end

  def response_time
    described_class.new(account_id: account.id, range: range)
  end

  it 'conta a primeira resposta pública depois da primeira mensagem do cliente, e a mediana' do
    [60, 120, 600, 900].each do |seconds|
      start = 3.days.ago
      message(conversation_at(start), :outgoing, start + seconds)
    end

    expect(response_time.payload).to eq(days: 30, median_seconds: 360, answered: 4, unanswered: 0, slow: 2, target_seconds: 300)
  end

  it 'ignora boas-vindas, atividade, nota privada, automação e disparos de campanha' do
    start = 2.days.ago
    conversation = conversation_at(start)
    message(conversation, :template, start + 5)
    message(conversation, :activity, start + 6)
    message(conversation, :outgoing, start + 7, private: true)
    message(conversation, :outgoing, start + 8, content_attributes: { 'automation_rule_id' => 3 })
    message(conversation, :outgoing, start + 9, additional_attributes: { 'campaign_id' => 4 })
    message(conversation, :outgoing, start + 10, additional_attributes: { 'whatsapp_api_campaign_id' => 5 })
    message(conversation, :outgoing, start + 1800)

    expect(response_time.by_conversation).to eq(conversation.id => { seconds: 1800, answered: true })
  end

  it 'começa no menor toque do período (com 1 min de tolerância) e não usa mensagem anterior a ele' do
    start = 2.days.ago
    conversation = conversation_at(start - 1.day, touches: [start + 30, start + 1.hour])
    message(conversation, :outgoing, start - 1.day + 10)
    message(conversation, :incoming, start)
    message(conversation, :outgoing, start + 90)

    expect(response_time.by_conversation).to eq(conversation.id => { seconds: 90, answered: true })
  end

  it 'sem resposta conta só depois do prazo; a entrada recente ainda está no prazo' do
    conversation_at(1.hour.ago)
    conversation_at(2.minutes.ago)

    expect(response_time.payload).to include(median_seconds: nil, answered: 0, unanswered: 1)
  end

  it 'fica fora quem não tem toque no período' do
    old = conversation_at(40.days.ago)
    message(old, :outgoing, 40.days.ago + 60)

    expect(response_time.payload).to include(answered: 0, unanswered: 0)
  end

  it 'faz uma consulta só, qualquer que seja o número de conversas' do
    5.times { |index| message(conversation_at(3.days.ago), :outgoing, 3.days.ago + (index * 100) + 1) }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { response_time.payload }

    expect(queries.size).to eq(1)
  end
end
