require 'rails_helper'

# #1702: a reação que chega pelo webhook vira o selo na mensagem reagida (Cloud, 360dialog e caixa híbrida), sem
# balão, sem contato novo e sem reabrir a conversa. Com agente da Autonomia na caixa, a mensagem sintética dele
# continua nascendo como antes (ReactionMaterializer) E o selo também.
describe Whatsapp::IncomingReactionExtension do
  # O canal 360dialog registra o webhook ao nascer (e nasce no let! abaixo).
  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    inbox.account.enable_features!('conversa_cara_do_canal')
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:wa_id) { '5511937016094' }
  let(:contact) { create(:contact, account: inbox.account, phone_number: "+#{wa_id}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: wa_id) }
  let(:conversation) do
    create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account, status: :resolved)
  end
  let!(:reacted) do
    create(:message, message_type: :outgoing, content: 'Segue a proposta', conversation: conversation, account: inbox.account,
                     inbox: inbox, source_id: 'wamid.REAGIDA')
  end

  def reaction_message(emoji: '👍', message_id: 'wamid.REAGIDA', id: 'wamid.EVENTO')
    reaction = { message_id: message_id, emoji: emoji }.compact
    { from: wa_id, id: id, timestamp: '1792141200', type: 'reaction', reaction: reaction }
  end

  def cloud_params(message)
    {
      phone_number: channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: { contacts: [{ profile: { name: 'Cliente' }, wa_id: wa_id }], messages: [message] } }] }]
    }.with_indifferent_access
  end

  def cloud_perform(message = reaction_message)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: cloud_params(message)).perform
  end

  def reactions
    reacted.reload.content_attributes['reactions']
  end

  describe 'Cloud API' do
    it 'grava o selo e não cria mensagem, contato nem conversa' do
      conversation

      expect { cloud_perform }.not_to change(Message, :count)
      expect(reactions).to contain_exactly(hash_including('emoji' => '👍', 'sender_type' => 'Contact', 'sender_id' => contact.id))
      expect(Contact.count).to eq(1)
      expect(inbox.conversations.count).to eq(1)
    end

    it 'com a chave desligada, descarta a reação como o Chatwoot' do
      inbox.account.disable_features!('conversa_cara_do_canal')

      expect { cloud_perform }.not_to change(Message, :count)
      expect(reactions).to be_nil
    end

    it 'não reabre a conversa resolvida' do
      cloud_perform

      expect(conversation.reload).to be_resolved
    end

    it 'tira o selo quando a reação é removida (sem emoji)' do
      cloud_perform
      cloud_perform(reaction_message(emoji: nil, id: 'wamid.EVENTO2'))

      expect(reactions).to be_nil
    end

    it 'ignora reação a mensagem que não está no banco' do
      expect { cloud_perform(reaction_message(message_id: 'wamid.SUMIU')) }.not_to change(Message, :count)
      expect(reactions).to be_nil
    end

    it 'eco de reação feita pelo celular da empresa segue descartado' do
      params = { phone_number: channel.phone_number, object: 'whatsapp_business_account',
                 entry: [{ changes: [{ value: { message_echoes: [reaction_message.merge(to: wa_id)] } }] }] }.with_indifferent_access

      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params, outgoing_echo: true)

      expect { service.perform }.not_to change(Message, :count)
      expect(reactions).to be_nil
    end

    it 'falha do selo não quebra o recebimento' do
      allow(Whatsapp::ReactionRecorder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

      expect { cloud_perform }.not_to raise_error
    end
  end

  describe '360dialog' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }

    it 'grava o selo pelo mesmo serviço' do
      params = { contacts: [{ profile: { name: 'Cliente' }, wa_id: wa_id }], messages: [reaction_message] }.with_indifferent_access

      expect { Whatsapp::IncomingMessageService.new(inbox: inbox, params: params).perform }.not_to change(Message, :count)
      expect(reactions.pluck('emoji')).to eq(['👍'])
    end
  end

  describe 'caixa híbrida' do
    it 'acha a mensagem que saiu pelo WhatsApp API e ainda guarda o id físico' do
      reacted.update!(source_id: '3EB0AAAA')
      wamid = "wamid.#{Base64.strict_encode64("#{[0x18, 8].pack('C*')}3EB0AAAA")}"

      cloud_perform(reaction_message(message_id: wamid))

      expect(reactions.pluck('emoji')).to eq(['👍'])
    end
  end

  describe 'com agente da Autonomia na caixa' do
    let(:agent_inbox) { instance_double(Autonomia::Agents::AgentInbox, agent: nil) }

    before do
      allow(Autonomia::Agents::QuemResponde).to receive(:porta_da_caixa).and_return(agent_inbox)
      allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(agent_inbox)
      allow(Autonomia::Agents::Config).to receive(:operate_reactions_enabled?).and_return(true)
    end

    it 'cria a mensagem sintética do agente E grava o selo' do
      expect { cloud_perform }.to change(Message, :count).by(1)

      synthetic = conversation.messages.find_by(source_id: 'wamid.EVENTO')
      expect(synthetic).to be_incoming
      expect(synthetic.content_attributes['autonomia_reaction']).to include('emoji' => '👍', 'reacted_source_id' => 'wamid.REAGIDA')
      expect(reactions.pluck('emoji')).to eq(['👍'])
    end

    it 'o agente roda antes do selo e o selo não pega a trava do evento' do
      allow(Whatsapp::MessageDedupLock).to receive(:new).and_call_original

      cloud_perform

      expect(Whatsapp::MessageDedupLock).to have_received(:new).with('wamid.EVENTO').once
    end

    it 'falha do selo não impede a mensagem do agente' do
      allow(Whatsapp::ReactionRecorder).to receive(:new).and_raise(StandardError)

      expect { cloud_perform }.to change(Message, :count).by(1)
    end

    # Combinado com os Agentes IA (17/10): a reação dá UM turno à IA, o da mensagem sintética. O selo é atualização da
    # mensagem reagida (message.updated), que o Operate não ouve; nenhuma outra mensagem nasce.
    it 'gera um único turno para a IA: só a mensagem sintética dispara message.created' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      cloud_perform

      synthetic = conversation.messages.find_by(source_id: 'wamid.EVENTO')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::MESSAGE_CREATED, anything, hash_including(message: synthetic)).once
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::MESSAGE_CREATED, anything, anything).once
      expect(reactions.pluck('emoji')).to eq(['👍'])
    end

    it 'com as reações do agente desligadas: só o selo, sem turno' do
      allow(Autonomia::Agents::Config).to receive(:operate_reactions_enabled?).and_return(false)

      expect { cloud_perform }.not_to change(Message, :count)
      expect(reactions.pluck('emoji')).to eq(['👍'])
    end

    it 'reação removida: o agente ignora e o selo some' do
      cloud_perform

      expect { cloud_perform(reaction_message(emoji: nil, id: 'wamid.EVENTO2')) }.not_to change(Message, :count)
      expect(reactions).to be_nil
      expect(conversation.messages.find_by(source_id: 'wamid.EVENTO')).to be_present
    end
  end
end
