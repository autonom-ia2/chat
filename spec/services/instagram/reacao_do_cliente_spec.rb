require 'rails_helper'

# #2113 — casos de borda do recebimento da reação do Instagram (o fluxo inteiro está no spec do job).
describe Instagram::ReacaoDoCliente do
  let(:account) do
    create(:account).tap do |conta|
      conta.enable_features!('conversa_instagram')
      conta.save!
    end
  end
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: 'ig-customer-1') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:reacted) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, source_id: 'mid.A')
  end

  def receber(reaction, timestamp: 1_792_000_000_000)
    messaging = { timestamp: timestamp, reaction: reaction }.with_indifferent_access
    described_class.new(messaging: messaging, inbox: inbox).perform
  end

  def reactions
    reacted.reload.content_attributes['reactions']
  end

  it "react sem emoji não vira 'tirar a reação'" do
    receber({ mid: 'mid.A', action: 'react', emoji: '👍' })
    receber({ mid: 'mid.A', action: 'react', reaction: 'love' }, timestamp: 1_792_000_060_000)

    expect(reactions.pluck('emoji')).to eq(['👍'])
  end

  it 'ação desconhecida é ignorada' do
    receber({ mid: 'mid.A', action: 'other', emoji: '👍' })

    expect(reactions).to be_nil
  end

  it 'aceita o timestamp em segundos também' do
    receber({ mid: 'mid.A', action: 'react', emoji: '👍' }, timestamp: 1_792_000_000)

    expect(reactions.first['at']).to eq(Time.zone.at(1_792_000_000).iso8601)
  end

  it 'reação mais antiga que chega atrasada não desfaz a mais nova' do
    receber({ mid: 'mid.A', action: 'react', emoji: '😂' }, timestamp: 1_792_000_060_000)
    receber({ mid: 'mid.A', action: 'react', emoji: '👍' })

    expect(reactions.pluck('emoji')).to eq(['😂'])
  end
end
