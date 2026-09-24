require 'rails_helper'

# A NOTA DA EQUIPE NO ENCAMINHAMENTO (conversa 7057, 24/09/2026). A busca de atividade estourou o tempo duas vezes, a
# Lia passou a conversa para a equipe, e a equipe não soube por quê: a recusa só ia para o log. O que se prova:
#   a recusa com conversa fica guardada pelo código, e só pelo código;
#   o encaminhamento, pelo sinal da Lia ou pelo CRM, vira uma nota PRIVADA com a frase de cada motivo e a contagem;
#   uma vez por encaminhamento, e nada quando não houve recusa;
#   Redis fora do ar não derruba o encaminhamento.
RSpec.describe Autonomia::Agents::NotaDoEncaminhamento do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:recentes) { Autonomia::Agents::Tools::RecusasRecentes }

  before do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
    recentes.retirar(conversation.id)
  end

  def recusar(codigo)
    Autonomia::Agents::Tools::Recusa.registrar(codigo, slug: 'buscar_atividade', conversa: conversation.id, agente: agent)
  end

  def notas
    conversation.messages.where(private: true)
  end

  describe 'o registro' do
    it 'guarda o código de cada recusa com conversa, na ordem, e esvazia ao ser lido' do
      recusar('busca_de_atividade_indisponivel')
      recusar('atividade_sem_termos')

      expect(recentes.retirar(conversation.id)).to eq(%w[busca_de_atividade_indisponivel atividade_sem_termos])
      expect(recentes.retirar(conversation.id)).to eq([])
    end

    it 'recusa sem conversa (Testar, Copiloto) ou com código fora da forma não guarda nada' do
      Autonomia::Agents::Tools::Recusa.registrar('busca_de_atividade_indisponivel', slug: 'buscar_atividade', conversa: nil)
      Autonomia::Agents::Tools::Recusa.registrar('não é código', slug: 'buscar_atividade', conversa: conversation.id)

      expect(recentes.retirar(conversation.id)).to eq([])
    end

    it 'guarda no máximo o teto, e com validade' do
      (recentes::TETO + 5).times { recusar('busca_de_atividade_indisponivel') }

      chave = format(recentes::CHAVE, conversa: conversation.id)
      expect(Redis::Alfred.llen(chave)).to eq(recentes::TETO)
      expect(Redis::Alfred.ttl(chave)).to be_between(1, recentes::VALIDADE.to_i)
    end
  end

  describe 'a nota' do
    it 'diz à equipe o que a IA não conseguiu, com a frase de cada motivo e a contagem, em mensagem privada' do
      2.times { recusar('busca_de_atividade_indisponivel') }
      recusar('consulta_de_cep_indisponivel')

      nota = described_class.postar(conversation)

      motivos = Autonomia::Agents::Tools::Recusa::MOTIVOS
      expect(nota.content).to eq(
        "#{described_class::TITULO}\n" \
        "- #{motivos['busca_de_atividade_indisponivel']} (2 vezes)\n" \
        "- #{motivos['consulta_de_cep_indisponivel']}"
      )
      expect(nota).to have_attributes(private: true, sender: agent_bot)
      expect(nota.content_attributes[described_class::CHAVE]).to be(true)
    end

    it 'uma vez por encaminhamento, e nenhuma quando não houve recusa' do
      recusar('busca_de_atividade_indisponivel')

      described_class.postar(conversation)
      described_class.postar(conversation)

      expect(notas.count).to eq(1)
    end

    it 'Redis fora do ar: sem nota e sem erro' do
      allow(Redis::Alfred).to receive(:lrange).and_raise(Redis::CannotConnectError)

      expect(described_class.postar(conversation)).to be_nil
      expect(notas).to be_empty
    end
  end

  # O caminho real da 7057: a recusa na ferramenta e o sinal de encaminhamento da Lia no mesmo turno.
  describe 'no encaminhamento pelo sinal da Lia' do
    around do |example|
      with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
        example.run
      end
    end

    before do
      conversation.update!(assignee_agent_bot_id: agent_bot.id)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'cota a corretora')
      answer = Autonomia::Agents::AnswerResult.new(reply: 'Alguém da equipe assume a conversa por aqui.', confidence: 0.9,
                                                   handoff: { should: true, reason: 'ai_unavailable' })
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        recusar('busca_de_atividade_indisponivel')
        instance_double(Autonomia::Agents::Answerer, answer: answer)
      end
    end

    it 'o cliente ouve a Lia, e a equipe recebe o motivo em nota privada' do
      agent_inbox = Autonomia::Agents::AgentInbox.find_by!(inbox: inbox)

      Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox).perform

      expect(conversation.messages.where(private: false, message_type: :outgoing).pluck(:content))
        .to eq(['Alguém da equipe assume a conversa por aqui.'])
      expect(notas.pluck(:content))
        .to eq(["#{described_class::TITULO}\n- #{Autonomia::Agents::Tools::Recusa::MOTIVOS['busca_de_atividade_indisponivel']}"])
    end
  end
end
