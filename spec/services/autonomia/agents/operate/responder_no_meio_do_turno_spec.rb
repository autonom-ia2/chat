require 'rails_helper'

# #3225: o lado do Responder na leitura do meio do turno (`Operate::NoMeioDoTurno`). O que é legível passa por um método
# só (`texto_no_meio_do_turno`), o mesmo que os prepends do WAHA completam: texto e áudio transcrito sim; imagem,
# documento, apagada, toque numa opção e recuperação pendente do Híbrido não (a leitura para nelas). E o leitor só existe
# no turno de uma mensagem do cliente: o turno da passagem e o de evento nunca leem, mesmo com a flag.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let!(:ancora) { recebe('França, 15 a 20/01, 40 anos') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'true') { example.run }
  end

  def recebe(texto, **extras)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto, **extras)
  end

  def responder
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ancora.id)
  end

  def texto(mensagem)
    responder.send(:texto_no_meio_do_turno, mensagem)
  end

  describe 'o que é legível' do
    it 'texto: o próprio texto' do
      expect(texto(recebe('Conhece lá?'))).to eq('Conhece lá?')
    end

    it 'imagem, com ou sem legenda: não', :aggregate_failures do
      [recebe(''), recebe('olha a foto')].each do |foto|
        foto.attachments.new(account_id: account.id, file_type: :image)
        expect(texto(foto)).to be_nil
      end
    end

    it 'documento: não' do
      documento = recebe('segue o passaporte')
      documento.attachments.new(account_id: account.id, file_type: :file)
      expect(texto(documento)).to be_nil
    end

    it 'apagada pelo cliente: não (a regra do histórico, pelo prepend do WAHA)' do
      apagada = recebe('Conhece lá?', content_attributes: { Waha::RichNative::TurnKinds::DELETED_KEY => Time.current.iso8601 })
      expect(texto(apagada)).to be_nil
    end

    it 'toque numa opção (com a resposta à oferta): não, só a pergunta do turno lê como dado' do
      toque = recebe('Sim', content_attributes: { 'selected_option' => { 'id' => 'sim', 'title' => 'Sim' }, 'in_reply_to' => ancora.id })
      expect(texto(toque)).to be_nil
    end

    it 'recuperação do WhatsApp Híbrido pendente: não' do
      pendente = recebe('', content_attributes: { WhatsappHybrid::UnsupportedRecovery::STATE_KEY => WhatsappHybrid::UnsupportedRecovery::PENDING })
      expect(texto(pendente)).to be_nil
    end

    describe 'áudio' do
      let(:transcricoes) { instance_double(Crm::Ai::TranscriptionClient, transcribe: 'texto pago') }
      let(:audio) do
        recebe('').tap do |mensagem|
          anexo = mensagem.attachments.create!(account: account, file_type: :audio, external_url: 'https://exemplo.invalid/audio.ogg')
          anexo.update!(meta: { 'transcribed_text' => 'conhece lá?' })
        end
      end

      before do
        allow(Crm::Ai::CredentialResolver).to receive(:new)
          .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: 'teste' }))
        allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(transcricoes)
      end

      it 'transcrito: a transcrição, com o rótulo da pergunta', :aggregate_failures do
        expect(texto(Message.find(audio.id))).to eq("#{Autonomia::Agents::Operate::NoMeioDoTurno::AUDIO_TRANSCRITO}conhece lá?")
        expect(transcricoes).not_to have_received(:transcribe)
      end

      it 'com a leitura de mídia desligada: não' do
        with_modified_env(AI_AGENT_MEDIA: 'false') { expect(texto(Message.find(audio.id))).to be_nil }
      end
    end
  end

  describe 'quem tem leitor' do
    it 'o turno de uma mensagem do cliente, com a flag: sim' do
      expect(responder.send(:leitura)).to be_a(Autonomia::Agents::Operate::LeituraNoTurno)
    end

    it 'sem a flag: não' do
      account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      expect(described_class.new(conversation: conversation.reload, agent_inbox: agent_inbox, reply_to_message_id: ancora.id)
               .send(:leitura)).to be_nil
    end

    it 'o turno da passagem e o de evento: não, mesmo com a flag, e nem perguntam', :aggregate_failures do
      allow(Autonomia::Agents::Operate::LeituraNoTurno).to receive(:ligada?).and_call_original
      passagem = Autonomia::Agents::Operate::ResponderAPassagem.new(conversation: conversation, agent_inbox: agent_inbox, passagem: nil)
      evento = Autonomia::Agents::Operate::ResponderAoEvento.new(conversation: conversation, agent_inbox: agent_inbox, evento: nil)

      expect(passagem.send(:leitura)).to be_nil
      expect(evento.send(:leitura)).to be_nil
      expect(Autonomia::Agents::Operate::LeituraNoTurno).not_to have_received(:ligada?)
    end
  end
end
