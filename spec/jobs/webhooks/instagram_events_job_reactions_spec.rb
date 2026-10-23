require 'rails_helper'

# #2113 — a reação do cliente no Instagram vira o selo na mensagem reagida (react, troca, unreact), na caixa Instagram e
# no Instagram ligado por página do Facebook. O caminho do agente da Autonomia continua igual.
describe Webhooks::InstagramEventsJob do
  let(:account) { create(:account) }
  let(:business_id) { 'ig-business-1' }
  let(:customer_id) { 'ig-customer-1' }

  def reaction_entry(action:, emoji: nil, mid: 'mid.REAGIDA', timestamp: 1_792_000_000_000)
    reaction = { mid: mid, action: action, reaction: emoji && 'love', emoji: emoji }.compact
    [{ id: business_id, time: timestamp,
       messaging: [{ sender: { id: customer_id }, recipient: { id: business_id }, timestamp: timestamp, reaction: reaction }] }]
      .map(&:with_indifferent_access)
  end

  def reactions
    reacted.reload.content_attributes['reactions']
  end

  shared_examples 'grava a reação do cliente' do
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: customer_id) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
    let!(:reacted) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Proposta',
                       source_id: 'mid.REAGIDA')
    end

    before do
      account.enable_features!('conversa_instagram')
      account.save!
    end

    it 'react: grava o emoji na mensagem reagida, sem criar mensagem' do
      expect { described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️')) }.not_to change(Message, :count)

      expect(reactions).to contain_exactly(include('emoji' => '❤️', 'sender_type' => 'Contact', 'sender_id' => contact.id,
                                                   'at' => Time.zone.at(1_792_000_000).iso8601))
    end

    it 'troca: a reação nova do cliente substitui a anterior' do
      described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️'))
      described_class.perform_now(reaction_entry(action: 'react', emoji: '😂', timestamp: 1_792_000_060_000))

      expect(reactions.pluck('emoji')).to eq(['😂'])
    end

    it 'unreact: tira a reação do cliente' do
      described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️'))
      described_class.perform_now(reaction_entry(action: 'unreact', timestamp: 1_792_000_060_000))

      expect(reacted.reload.content_attributes).not_to have_key('reactions')
    end

    it 'mid desconhecido: nada muda e o job não quebra' do
      expect { described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️', mid: 'mid.OUTRA')) }.not_to raise_error

      expect(reactions).to be_nil
    end

    it 'sem a chave conversa_instagram: a reação segue ignorada' do
      account.disable_features!('conversa_instagram')
      account.save!

      described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️'))

      expect(reactions).to be_nil
    end
  end

  context 'with Instagram login' do
    let(:inbox) { create(:channel_instagram, account: account, instagram_id: business_id).inbox }

    it_behaves_like 'grava a reação do cliente'
  end

  context 'with Instagram via Facebook page' do
    let(:channel) { create(:channel_instagram_fb_page, account: account, instagram_id: business_id) }
    let(:inbox) { create(:inbox, channel: channel, account: account, greeting_enabled: false) }

    it_behaves_like 'grava a reação do cliente'
  end

  context 'with the Autonomia agent path' do
    let!(:inbox) { create(:channel_instagram, account: account, instagram_id: business_id).inbox }

    before { allow(Autonomia::Agents::Config).to receive(:operate_reactions_enabled?).and_return(true) }

    it 'continua chamando o ReactionMaterializer com os mesmos argumentos no react' do
      allow(Autonomia::Agents::Operate::ReactionMaterializer).to receive(:call)

      described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️'))

      expect(Autonomia::Agents::Operate::ReactionMaterializer).to have_received(:call).with(
        inbox: inbox, reacted_source_id: 'mid.REAGIDA', emoji: '❤️', event_source_id: 'ig_reaction:mid.REAGIDA:1792000000000'
      )
    end

    it 'não chama o ReactionMaterializer no unreact' do
      allow(Autonomia::Agents::Operate::ReactionMaterializer).to receive(:call)

      described_class.perform_now(reaction_entry(action: 'unreact'))

      expect(Autonomia::Agents::Operate::ReactionMaterializer).not_to have_received(:call)
    end

    it 'falha ao gravar o selo não impede o agente' do
      allow(Whatsapp::ReactionRecorder).to receive(:new).and_raise(StandardError)
      allow(Autonomia::Agents::Operate::ReactionMaterializer).to receive(:call)
      account.enable_features!('conversa_instagram')
      account.save!

      described_class.perform_now(reaction_entry(action: 'react', emoji: '❤️'))

      expect(Autonomia::Agents::Operate::ReactionMaterializer).to have_received(:call)
    end
  end
end
