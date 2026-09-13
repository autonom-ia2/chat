require 'rails_helper'

# A CONFIRMAÇÃO DO FECHAMENTO NO INTERVALO CURTO (fatia 2 do #420) — pelo motor, com o relógio parado.
#
# Na prova real da fatia 1, depois de todas as seguradoras responderem, a segunda leitura (a que confirma e
# fecha a cotação) esperou o intervalo da tentativa: 21 s, o último da progressão padrão. Aqui a leitura que
# vê todas com desfecho agenda a seguinte no primeiro intervalo da progressão. A guarda das duas leituras
# seguidas (fatia 1) não muda: a primeira leitura não fecha.
#
# O motor e a ferramenta de cotação são os de verdade; o conector `mock` responde a leitura (dados
# sintéticos), e o download do PDF é o do WebMock.
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
  let(:config) { Autonomia::Agents::Tools::AsyncConfig }
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  # A tentativa da prova real em que a leitura já vinha no fim da progressão (21 s).
  let(:tentativa_tardia) { 12 }

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
    allow(mock).to receive(:quote_proposal).and_call_original
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
    stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf')
      .to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
  end

  def oferta(code, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    amount ? base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' }) : base
  end

  def portal_responde(ofertas)
    allow(mock).to receive(:quote_result).and_return({ 'quote_id' => 'q-1:1', 'status' => 'partial', 'offers' => ofertas })
  end

  def todas_com_desfecho
    [oferta('8', 'quoted', 2119.18), oferta('47', 'declined'), oferta('11', 'auth_required')]
  end

  # A execução como o motor a deixa depois de uma leitura com uma seguradora ainda correndo.
  def cotacao_correndo
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1', cotacao::DELIVERED_KEY => [],
                                  cotacao::ACIONADAS_KEY => %w[11 47 8] })
    run
  end

  def passada(run, tentativa)
    described_class.new.perform(run.id, tentativa)
    run.reload
  end

  # -> o instante em que a passada seguinte desta execução foi agendada.
  def agendada_para(run, tentativa)
    job = enqueued_jobs.find { |item| item[:job] == described_class && item[:args] == [run.id, tentativa] }
    job && Time.zone.at(job[:at])
  end

  it 'os números da progressão padrão que o teste usa: 3 s no primeiro intervalo e 21 s na tentativa tardia' do
    expect(config.interval_for(agent, 0)).to eq(3.seconds)
    expect(config.interval_for(agent, tentativa_tardia)).to eq(21.seconds)
  end

  it 'a leitura com todas com desfecho agenda a confirmação em 3 s, e não nos 21 s da tentativa' do
    freeze_time do
      # Arrange
      run = cotacao_correndo
      portal_responde(todas_com_desfecho)

      # Act
      passada(run, tentativa_tardia)

      # Assert — não fechou (a guarda das duas leituras) e a seguinte vem no primeiro intervalo
      expect(run.status).to eq('running')
      expect(agendada_para(run, tentativa_tardia + 1)).to eq(3.seconds.from_now)
    end
  end

  it 'o controle: a leitura com seguradora ainda correndo continua agendando no intervalo da tentativa' do
    freeze_time do
      run = cotacao_correndo
      portal_responde(todas_com_desfecho + [oferta('19', 'running')])

      passada(run, tentativa_tardia)

      expect(agendada_para(run, tentativa_tardia + 1)).to eq(21.seconds.from_now)
    end
  end

  # O GANHO, NA LINHA DO TEMPO: da leitura que vê todas com desfecho até a execução fechar. Antes desta
  # fatia, 21 s; agora, 3 s.
  it 'da ultima resposta ao fechamento da cotação passam 3 s, com precos, comparativo e fecho' do
    run = cotacao_correndo
    portal_responde(todas_com_desfecho)
    inicio = Time.zone.now.change(usec: 0)

    travel_to(inicio) { passada(run, tentativa_tardia) }
    confirmacao = agendada_para(run, tentativa_tardia + 1)
    travel_to(confirmacao) { passada(run, tentativa_tardia + 1) }

    expect(confirmacao - inicio).to eq(3.0)
    expect(run.status).to eq('done')
    expect(conversation.messages.reload.where(sender_type: 'AgentBot').count).to eq(3)
  end

  it 'a confirmação curta respeita a progressão configurada no agente' do
    freeze_time do
      agent.update!(config: agent.config.merge('async_poll_intervals' => [7, 30]))
      run = cotacao_correndo
      portal_responde(todas_com_desfecho)

      passada(run, tentativa_tardia)

      expect(agendada_para(run, tentativa_tardia + 1)).to eq(7.seconds.from_now)
    end
  end

  it 'a leitura que repete a anterior sem fechar volta ao intervalo da tentativa' do
    freeze_time do
      run = cotacao_correndo
      run.record_attempt!(handle: { cotacao::ACIONADAS_KEY => %w[11 19 47 8], cotacao::LEITURA_ASSENTADA_KEY => %w[11 47 8] })
      portal_responde(todas_com_desfecho)

      passada(run, tentativa_tardia)

      expect(run.status).to eq('running')
      expect(agendada_para(run, tentativa_tardia + 1)).to eq(21.seconds.from_now)
    end
  end
end
