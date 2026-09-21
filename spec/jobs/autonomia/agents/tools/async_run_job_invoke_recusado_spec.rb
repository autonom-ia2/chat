require 'rails_helper'

# INVOCAÇÃO RECUSADA NÃO É "PODE TER COTADO", com a ferramenta de cotação de verdade.
#
# A fronteira que protege o dinheiro (entrega 5) separa dois mundos: falha antes da chamada paga
# volta a intenção atrás e a execução tenta de novo; falha depois dela mantém a intenção, porque o
# portal pode ter cotado, e aí só sobra mais UMA tentativa antes de mandar o cliente para a fila.
#
# Até 20/09/2026 tudo que não fosse recusa explícita caía no segundo mundo, inclusive a invocação
# que o próprio serviço recusa — throttle, permissão, 5xx dele —, quando o adapter nem chega a
# rodar e o portal não é tocado. Em produção isso queimou as duas tentativas em 27 segundos e
# mandou o cliente para a fila, com o adapter registrando zero erros no mesmo minuto (conversa
# 6987, teste de um corretor convidado).
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  let(:intencoes) { Autonomia::Agents::ToolRun::INTENCOES }
  let(:duplicada) { Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA }
  let(:dados) do
    { segurado: { nome: 'Fulano', cpfCnpj: '04297912678' },
      configuracoes: { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' } }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true',
                      INSURANCE_CONNECTOR_MODE: 'mock') { example.run }
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    register_async_tool(cotacao)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(mock)
  end

  def recusa_do_servico(causa)
    Autonomia::Insurance::Connector::Error.new(:unavailable, 'connector invoke HTTP 429', {}, causa: causa)
  end

  def execucao
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'bike', 'dados' => dados },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
    run
  end

  it 'a invocação recusada não gasta tentativa nem marca a execução' do
    # Arrange — o serviço recusou a chamada: o adapter não rodou, nada foi cotado
    allow(mock).to receive(:quote_start).and_raise(recusa_do_servico(:invoke_recusado))
    run = execucao

    # Act
    described_class.new.perform(run.id, 0)

    # Assert — sem intenção pendurada e sem a marca que manda o corretor conferir o portal
    expect(run.reload.handle[intencoes].to_i).to eq(0)
    expect(run.handle).not_to have_key(duplicada)
  end

  it 'o handler que explodiu continua sendo incerteza: a intenção fica' do
    # Arrange — aqui o adapter rodou, então o portal pode ter sido chamado
    allow(mock).to receive(:quote_start).and_raise(recusa_do_servico(:handler_quebrou))
    run = execucao

    # Act
    described_class.new.perform(run.id, 0)

    # Assert
    expect(run.reload.handle[intencoes].to_i).to eq(1)
  end

  it 'a etiqueta da falha vai para o log, e sem texto do portal' do
    # Arrange
    allow(mock).to receive(:quote_start).and_raise(recusa_do_servico(:handler_quebrou))
    run = execucao
    allow(Rails.logger).to receive(:warn)

    # Act
    described_class.new.perform(run.id, 0)

    # Assert — categoria e porta, ambas nossas
    expect(Rails.logger).to have_received(:warn).with(%r{motivo=unavailable/handler_quebrou}).at_least(:once)
  end
end
