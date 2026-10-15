require 'rails_helper'

# chat#1489: modelo recuperado do celular com arquivo no cabeçalho. O texto vai ao histórico com uma linha avisando que
# o arquivo não foi lido. A linha é só contexto do modelo: nunca vai ao `content` da Message nem à resposta ao cliente.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:note) { Autonomia::Agents::Operate::RecoveredHeaderNote::NOTES['image'] }
  let(:captured) { {} }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  def recebida(texto, atributos = {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: texto, content_attributes: atributos)
  end

  def historico
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).send(:history).pluck(:content)
  end

  describe 'histórico' do
    it 'imagem no cabeçalho: o texto e a linha de que a imagem não foi lida' do
      recebida('Sua fatura está disponível.', 'hybrid_recovery' => 'recovered', 'hybrid_recovery_header' => 'image')

      expect(historico).to eq(["Sua fatura está disponível.\n[a mensagem tinha uma imagem que não foi lida]"])
    end

    it 'outro arquivo no cabeçalho: a linha do arquivo' do
      recebida('Contrato anexo.', 'hybrid_recovery_header' => 'media')

      expect(historico).to eq(["Contrato anexo.\n[a mensagem tinha um arquivo que não foi lido]"])
    end

    it 'mensagem comum: só o texto, como antes' do
      recebida('Oi')

      expect(historico).to eq(['Oi'])
    end

    it 'a linha não toca o content da Message' do
      message = recebida('Sua fatura está disponível.', 'hybrid_recovery_header' => 'image')

      historico

      expect(message.reload.content).to eq('Sua fatura está disponível.')
    end
  end

  describe 'resposta ao cliente' do
    let(:recovered) { recebida('Sua fatura está disponível.', 'hybrid_recovery' => 'recovered', 'hybrid_recovery_header' => 'image') }

    def answer_with(reply)
      result = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil })
      answerer = instance_double(Autonomia::Agents::Answerer, answer: result)
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**args|
        captured[:history] = args[:history]
        answerer
      end
    end

    before do
      conversation.update!(ai_assignee: agent_bot)
      recovered
    end

    def perform
      described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: recovered.id).perform
    end

    it 'o modelo recebe a linha no histórico' do
      answer_with('Vou verificar a fatura para você.')

      perform

      expect(captured[:history].last[:content]).to include(note)
    end

    it 'se o modelo repetir a linha, ela sai da resposta enviada' do
      answer_with("Recebi sua mensagem. #{note}\nVou verificar a fatura para você.")

      result = perform

      expect(result.status).to eq(:replied)
      expect(result.message.content).not_to include(note)
      expect(result.message.content).to eq("Recebi sua mensagem. \nVou verificar a fatura para você.")
      expect(conversation.messages.outgoing.pluck(:content).join).not_to include('[a mensagem tinha')
    end

    it 'se a resposta for só a linha, o turno fica em silêncio (nada vai ao cliente)' do
      answer_with(note)

      expect { perform }.not_to(change { conversation.messages.outgoing.count })
    end

    it 'resposta comum passa intacta' do
      answer_with('Vou verificar a fatura para você.')

      expect(perform.message.content).to eq('Vou verificar a fatura para você.')
    end
  end
end
