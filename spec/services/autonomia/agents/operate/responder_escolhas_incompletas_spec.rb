require 'rails_helper'

# ESCOLHAS INCOMPLETAS NÃO EMUDECEM A LIA EM SILÊNCIO (#380, rodada 3).
#
# `config['agente_de_cotacao']` presente e incompleta só nasce de escrita fora do Builder (SQL manual, um
# rollout errado): a partir daí `Agent#instrucao_do_sistema` levanta `Builder::EscolhasIncompletas` na
# montagem do prompt — a recusa certa, uma variável nunca chega ao modelo como `$nomeAgente`. Mas o
# Responder resgatava isso no `rescue StandardError` genérico: `warn` no log, turno mudo, e o corretor via
# silêncio para TODO cliente sem ver a causa. Agora o Responder registra `skipped_escolhas_incompletas`
# no EventLogger, uma vez por conversa, antes do resgate largo — sem engolir nada que já não engolia.
#
# O Answerer NÃO é dublado: o erro tem de nascer no caminho real (`PromptBuilder#instructions`). Dublada
# é só a credencial, para o `generate` chegar à montagem do prompt; o cliente de IA nunca é chamado.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:chave) { Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA }
  let(:lia) { Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: lia, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cliente_de_ia) { instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: '{}' }) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    # Escrita fora do Builder: a chave fica sem `horario`.
    lia.update!(config: lia.config.merge(chave => lia.config[chave].except('horario')))
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    # O `new` do cliente é avaliado ANTES dos argumentos (`pb.instructions`, onde o erro nasce): o que
    # prova que o modelo não foi chamado é a chamada em si, `create_with_tool_executor`.
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_de_ia)
    allow(Rails.logger).to receive(:warn).and_call_original
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quero cotar')
  end

  def perform
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
  end

  it 'stays silent, never calls the model, and records skipped_escolhas_incompletas with the field name' do
    # Act
    result = perform

    # Assert — mudo como antes, mas registrado.
    expect(result.status).to eq(:silenced)
    expect(cliente_de_ia).not_to have_received(:create_with_tool_executor)
    expect(conversation.messages.outgoing.count).to eq(0)
    event = Autonomia::Agents::AgentEvent.skipped_escolhas_incompletas.last
    expect(event).to have_attributes(conversation_id: conversation.id, autonomia_agent_id: lia.id,
                                     handoff_reason: 'escolhas_incompletas')
    expect(Rails.logger).to have_received(:warn).with(/escolhas_incompletas.*campo=horario/)
  end

  it 'records the event once per conversation, not once per message' do
    # Act
    perform
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi?')
    perform

    # Assert
    expect(Autonomia::Agents::AgentEvent.skipped_escolhas_incompletas.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'records the event in another conversation of the same agent' do
    # Arrange
    outra = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: outra, message_type: :incoming, content: 'oi')

    # Act
    perform
    described_class.new(conversation: outra, agent_inbox: agent_inbox).perform

    # Assert
    expect(Autonomia::Agents::AgentEvent.skipped_escolhas_incompletas.pluck(:conversation_id))
      .to contain_exactly(conversation.id, outra.id)
  end

  # O evento não é handoff: a conversa continua com o espelho (comportamento de sempre no erro), e a aba
  # Desempenho não o soma aos handoffs.
  it 'is not counted as a handoff' do
    perform

    expect(Autonomia::Agents::AgentEvent.handoffs.count).to eq(0)
    expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
  end
end
