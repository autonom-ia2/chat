require 'rails_helper'

# chat#1489 × Fase 2 (#1606/#1669): com a equipe na janela, o histórico vai pelo HistoricoDaEquipe (moldura) e a linha
# de contexto da mensagem recuperada continua chegando ao modelo. O silêncio `so_contexto_interno` solta a posse do
# turno (como o `vazio`) e fica no painel como `skipped_recuperada_so_contexto`.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza', display_name: 'Ana') }
  let(:note) { Autonomia::Agents::Operate::RecoveredHeaderNote::NOTES['image'] }
  let(:historicos) { [] }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before { conversation.update!(ai_assignee: agent_bot) }

  def escreve(tipo, texto, sender: nil, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     sender: sender, **extras)
  end

  def ia_responde!(reply)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |history:, **|
      historicos << history
      resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil },
                                                      used_knowledge: [], answered_from_knowledge: false)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  # A Ana falou antes; depois chega a mensagem recuperada com imagem no cabeçalho (não lida).
  def recuperada_depois_da_ana
    escreve(:outgoing, 'Te mando a segunda via ainda hoje.', sender: ana)
    escreve(:incoming, 'Sua fatura de outubro está disponível.',
            content_attributes: { 'hybrid_recovery' => 'recovered', 'hybrid_recovery_header' => 'image' })
  end

  it 'com mensagem da equipe na janela, o histórico vai pela moldura e a IA recebe a linha de contexto' do
    expect(Autonomia::Agents::Operate::HistoricoDaEquipe.new(conversation: conversation).aplica?).to be(true)
    ia_responde!('Vou verificar a fatura.')
    recuperada = recuperada_depois_da_ana

    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: recuperada.id).perform

    historico = historicos.last
    expect(historico.first[:content]).to include('Ana, da equipe, escreveu ao cliente')
    expect(historico.last).to include(role: 'user')
    expect(historico.last[:content]).to include('Sua fatura de outubro está disponível.')
    expect(historico.last[:content]).to end_with(note)
  end

  describe 'resposta que era só a linha de contexto' do
    let(:posse) { 'job-posse-1' }

    it 'solta a posse do turno (PosseDoTurno.soltar com o valor da posse) e grava o evento do painel' do
      ia_responde!(note)
      recuperada = recuperada_depois_da_ana
      allow(Autonomia::Agents::Operate::PosseDoTurno).to receive(:soltar).and_call_original

      described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: recuperada.id,
                          posse: posse).perform

      expect(Autonomia::Agents::Operate::PosseDoTurno).to have_received(:soltar)
        .with(conversation.id, recuperada.id, agent_inbox.id, posse)
      event = Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id).last
      expect([event.event_type, event.handoff_reason]).to eq(%w[skipped_recuperada_so_contexto recuperada_so_contexto])
      expect(conversation.messages.outgoing.where(private: false, sender_type: 'AgentBot')).to be_empty
    end

    it 'o evento do painel sai uma vez por mensagem recuperada, mesmo com o turno retomado' do
      ia_responde!(note)
      recuperada = recuperada_depois_da_ana

      2.times do
        described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: recuperada.id,
                            posse: posse).perform
      end

      eventos = Autonomia::Agents::AgentEvent.skipped_recuperada_so_contexto.where(conversation_id: conversation.id)
      expect(eventos.pluck(:message_id)).to eq([recuperada.id])
    end

    it 'a chave da posse some do Redis' do
      ia_responde!(note)
      recuperada = recuperada_depois_da_ana
      chave = Autonomia::Agents::Operate::PosseDoTurno.chave(conversation.id, recuperada.id, agent_inbox.id)
      Redis::Alfred.set(chave, posse, ex: 60)

      described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: recuperada.id,
                          posse: posse).perform

      expect(Redis::Alfred.get(chave)).to be_nil
    end
  end
end
