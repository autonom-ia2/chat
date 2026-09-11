require 'rails_helper'

# ONDE O NÚMERO DE SEGURADORAS ACIONADAS PASSA A FICAR (entrega 7).
#
# Ele sempre existiu no resultado do portal e morria ali: o handle guardava só quem COTOU
# (`entregues`, que é o que já foi para o cliente), e quem recusou o risco ou recusou a nossa
# credencial não deixava rastro nenhum. A corretora paga pelas dezessete; o registro conhecia onze.
#
# A consulta é a entrega 7; aqui se prova a matéria-prima dela.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end

  # As dezessete seguradoras que o portal acionou nas TRÊS cotações reais da conta de teste, lidas em
  # 11/09/2026 por `agger quote result`: os mesmos códigos na renovação, na moto e no caminhão.
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  before { enable_test_encryption! }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  # UMA conexão por corretora (`provider` é único no escopo da conta), como em produção: duas
  # passadas do poll no mesmo exemplo reusam a mesma, e não criam uma segunda que o banco recusa.
  def ready_connection
    @ready_connection ||= begin
      record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      record.update!(status: 'ready')
      record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
      record
    end
  end

  def offer(code, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    amount ? base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' }) : base
  end

  def poll_com(offers, handle: { 'quote_id' => 'q1', 'entregues' => [] }, status: 'partial')
    ready_connection
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_result).and_return('status' => status, 'offers' => offers)
    described_class.new(agent: agent, params: { 'produto' => 'bike', 'dados' => '{}' })
                   .poll(handle: handle, attempt: 1)
  end

  describe 'seguradoras acionadas no handle' do
    # O CASO CONHECIDO, com o desenho do caminhão real de 11/09/2026: 1 cotou, 15 recusaram o risco e
    # 1 recusou a nossa credencial. São dezessete acionadas — contar só `quoted` + `declined` diria
    # dezesseis, e a que falta é justamente a que a corretora precisa ver (critério 4.5).
    it 'grava as dezessete, em qualquer status' do
      # Arrange
      offers = [offer('8', 'quoted', 900.0), offer('7', 'auth_required')] +
               (1..15).map { |i| offer("d#{i}", 'declined') }

      # Act
      progresso = poll_com(offers)

      # Assert
      expect(progresso.handle[described_class::ACIONADAS_KEY].size).to eq(17)
      expect(progresso.handle[described_class::ACIONADAS_KEY]).to include('8', '7', 'd1')
    end

    # A LISTA É A UNIÃO DAS CONSULTAS, não a foto da última. O portal responde em pedaços (medido em
    # 04/09/2026: 3 de 6 seguradoras em ~35 s, o negócio só assentou aos 392 s), e uma consulta que
    # devolvesse menos do que a anterior apagaria seguradoras que a corretora já tinha pagado.
    it 'nao perde quem ja tinha aparecido numa consulta anterior' do
      progresso = poll_com([offer('8', 'quoted', 900.0)],
                           handle: { 'quote_id' => 'q1', 'entregues' => ['8'],
                                     described_class::ACIONADAS_KEY => %w[3 9] })

      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq(%w[3 8 9])
    end

    it 'nao repete a mesma seguradora' do
      progresso = poll_com([offer('8', 'quoted', 900.0), offer('8', 'declined')])

      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq(['8'])
    end

    # UNIÃO É IDEMPOTENTE: RECONSULTAR NÃO MUDA NADA. O portal lista as dezessete desde a PRIMEIRA
    # consulta, e o poll consulta de novo a cada passada até o negócio assentar (medido em 04/09:
    # 392 s). Somar em vez de unir daria 34 na segunda passada e 340 na vigésima — e a medida
    # cobraria trezentas e quarenta seguradoras por UMA cotação, sem nada ficar vermelho.
    it 'nao infla a lista quando o portal repete o mesmo resultado' do
      # Arrange — o resultado que o portal devolve igual a cada consulta.
      offers = dezessete.map { |codigo| offer(codigo, 'declined') }

      # Act — duas passadas do poll sobre a MESMA cotação.
      primeira = poll_com(offers)
      segunda = poll_com(offers, handle: primeira.handle)

      # Assert — as mesmas dezessete nas duas, sem uma repetição sequer.
      expect(primeira.handle[described_class::ACIONADAS_KEY]).to eq(dezessete.sort)
      expect(segunda.handle[described_class::ACIONADAS_KEY]).to eq(dezessete.sort)
    end

    # A mesma regra no menor caso possível: um código que o handle JÁ TINHA e o resultado repete
    # entra uma vez só. É a interseção que os exemplos acima não tinham — e por isso `+` passava.
    it 'nao conta de novo quem o handle ja tinha' do
      progresso = poll_com([offer('8', 'quoted', 900.0)],
                           handle: { 'quote_id' => 'q1', 'entregues' => ['8'],
                                     described_class::ACIONADAS_KEY => %w[3 8] })

      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq(%w[3 8])
    end

    # Cotação em que o portal ainda não listou ninguém é MEDIDA COM ZERO, e não "sem medida": a
    # lista existe e está vazia. A diferença é o que a consulta da entrega 7 usa para não somar um
    # total que parece completo quando não é.
    it 'grava lista vazia quando o portal ainda nao listou ninguem' do
      progresso = poll_com([], status: 'running')

      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq([])
    end

    # O desfecho também carrega a medida: é a última escrita do handle antes de a execução encerrar.
    it 'grava tambem no fecho da cotação' do
      progresso = poll_com([offer('8', 'quoted', 900.0), offer('9', 'declined')], status: 'completed')

      expect(progresso.status).to eq(:done)
      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq(%w[8 9])
    end

    # Seguradora sem código no payload do portal não vira entrada vazia na lista: uma string vazia
    # contaria como uma seguradora a mais na conta de quem paga.
    it 'ignora oferta sem codigo de seguradora' do
      progresso = poll_com([offer('8', 'quoted', 900.0), { 'insurer' => {}, 'status' => 'declined' }])

      expect(progresso.handle[described_class::ACIONADAS_KEY]).to eq(['8'])
    end
  end

  # A MEDIDA LÊ A LINHA DA EXECUÇÃO, não o objeto que a consulta devolveu. Entre um e outro há o job:
  # ele tira as marcas nossas, mescla o resto NO BANCO (`handle || ?::jsonb`) e é isso que sobra para
  # `Insurance::Medida` somar. Uma chave que a ferramenta gravasse e o job descartasse (é o que
  # `MARCAS` faz com as nossas) passaria nos exemplos acima e sumiria em produção.
  describe 'a chave chega à linha da execução' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agente_de_cotacao) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Mia', agent_type: 'insurance_quote',
                                       status: :active, enabled: true, instruction: 'Cote.')
    end
    let!(:agent_inbox) do
      Autonomia::Agents::AgentInbox.create!(agent: agente_de_cotacao, inbox: inbox, account: account,
                                            agent_bot: agent_bot)
    end

    around do |example|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
    end

    it 'sobrevive ao job e fica no handle que a medida soma' do
      # Arrange — execução já submetida, como o job a deixa depois do `start`.
      account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_enabled' => true))
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_result).and_return(
        'status' => 'partial',
        'offers' => [offer('8', 'quoted', 900.0), offer('9', 'declined'), offer('7', 'auth_required')]
      )
      run = Autonomia::Agents::ToolRun.open!(agent: agente_de_cotacao, slug: described_class.slug,
                                             arguments: { 'produto' => 'bike', 'dados' => '{}' },
                                             scope: { conversation_id: conversation.id,
                                                      agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      run.record_attempt!(handle: { Autonomia::Agents::Tools::AsyncRunJob::SUBMITTED_KEY => true,
                                    'quote_id' => 'q1', 'entregues' => [] })

      # Act — uma passada de consulta do motor.
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 1)

      # Assert — três seguradoras acionadas, uma com preço: é o que a medida vai somar.
      expect(run.reload.handle[described_class::ACIONADAS_KEY]).to eq(%w[7 8 9])
      expect(run.handle[described_class::DELIVERED_KEY]).to eq(['8'])
      expect(Autonomia::Insurance::Medida.new(conta: account, inicio: nil, fim: nil).call)
        .to include(cotacoes: 1, seguradoras_acionadas: 3, seguradoras_com_preco: 1, cotacoes_sem_medida: 0)
    end
  end

  # A chave que a entrega 8 vai escrever. Ela já tem nome e já é lida pela medida; o que falta é a
  # ferramenta de proposta por seguradora, e o ponto de registro é o handle desta execução.
  it 'declara onde a proposta individual sera registrada (entrega 8)' do
    expect(described_class::PROPOSTAS_KEY).to eq('propostas')
  end
end
