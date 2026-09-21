require 'rails_helper'

# QUAL DOS TRÊS SILÊNCIOS ACONTECEU.
#
# O turno pode ficar mudo por três motivos muito diferentes: a instrução mandou calar (a pessoa só
# reconheceu, ou veio mensagem de robô), a IA falhou, ou ela devolveu texto vazio. Os três
# terminavam no mesmo `silenced`, sem rastro que os separasse.
#
# Em 21/09/2026, perguntado quantas vezes a Lia calou de propósito, não deu para responder: a única
# medida possível era contar mensagem de cliente sem resposta, que mistura os três e ainda inclui
# agrupamento de mensagens. Mesma cegueira que custou um dia de investigação no `unavailable`.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end

  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def responde_com(reply:, error: nil)
    resultado = Autonomia::Agents::AnswerResult.new(
      reply: reply, confidence: 0.0, handoff: { should: false, reason: nil },
      used_knowledge: [], answered_from_knowledge: false, raw_reply: reply, error: error
    )
    answerer = instance_double(Autonomia::Agents::Answerer, answer: resultado)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)
  end

  def silenciar_e_ler_log
    linhas = []
    allow(Rails.logger).to receive(:info) { |texto| linhas << texto.to_s }
    resultado = described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
    [resultado, linhas.grep(/\[autonomia\]\[operate\] silencio/)]
  end

  it 'o sinal da instrução é registrado como sinal, e nada é postado' do
    # Arrange — é o que a instrução manda emitir quando a pessoa só reconheceu
    responde_com(reply: 'conversation_closed_for_now')

    # Act
    resultado, registros = silenciar_e_ler_log

    # Assert
    expect(resultado.status).to eq(:silenced)
    expect(registros.join).to include('motivo=sinal')
    expect(conversation.messages.reload.where(message_type: :outgoing)).to be_empty
  end

  it 'a IA que não respondeu é registrada como falha, e não como decisão de calar' do
    # Arrange
    answerer = instance_double(Autonomia::Agents::Answerer, answer: nil)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)

    # Act
    resultado, registros = silenciar_e_ler_log

    # Assert — confundir os dois é o que impedia responder "quantas vezes ela calou de propósito?"
    expect(resultado.status).to eq(:silenced)
    expect(registros.join).to include('motivo=ia_falhou')
  end

  it 'resposta em branco é registrada como vazio' do
    # Arrange
    responde_com(reply: '   ')

    # Act
    resultado, registros = silenciar_e_ler_log

    # Assert
    expect(resultado.status).to eq(:silenced)
    expect(registros.join).to include('motivo=vazio')
  end

  it 'o turno que o humano assumiu no meio é registrado como não elegível, e não como falha' do
    # Arrange — responsável na conversa derruba a elegibilidade antes mesmo da chamada de IA
    conversation.update!(assignee: create(:user, account: account))

    # Act
    resultado, registros = silenciar_e_ler_log

    # Assert — o turno tinha o que dizer; calou porque deixou de ser nosso
    expect(resultado.status).to eq(:silenced)
    expect(registros.join).to include('motivo=nao_elegivel')
  end

  it 'o turno que responde não registra silêncio nenhum' do
    # Arrange — sem isto, logar em todo turno passaria despercebido e inflaria a contagem
    responde_com(reply: 'Boa tarde. Me diga a placa e eu já cotó.')

    # Act
    resultado, registros = silenciar_e_ler_log

    # Assert
    expect(resultado.status).to eq(:replied)
    expect(registros).to be_empty
  end

  it 'o registro é só os dois ids e o rótulo, nada do que foi escrito' do
    # Arrange — o motivo é rótulo nosso, de lista fechada
    responde_com(reply: 'conversation_closed_for_now')

    # Act
    _resultado, registros = silenciar_e_ler_log

    # Assert — linha inteira, não só o fim dela: texto enfiado no meio também reprovaria
    expect(registros).to eq(
      ["[autonomia][operate] silencio agent=#{agent.id} conv=#{conversation.id} motivo=sinal"]
    )
  end
end
