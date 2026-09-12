require 'rails_helper'

# DÚVIDA DE COBERTURA COM A COTAÇÃO CORRENDO — entrega 9 (#397), termos 1, 2, 4 e 5.
#
# A cena é a da conversa real: a cotação foi disparada e está `running` no portal quando o cliente
# pergunta "a assistência 24h da Porto cobre guincho?". O que se prova aqui é que o turno da dúvida
# CONSULTA e NÃO MEXE NA COTAÇÃO — a consulta às condições gerais é síncrona e não abre execução,
# então a linha de `autonomia_agent_tool_runs` sai do turno como entrou: uma só, `running`, sem
# `superseded` e sem uma segunda chamada ao portal.
#
# O CAMINHO É O REAL: o agente é o que o `Builder` cria (principal + especialista de auto), o
# catálogo do turno é o do `Answerer` (que esconde do principal o que o especialista reservou), e a
# ferramenta executada é a `InsuranceGeneralConditions` de verdade, contra o `/query` dublado por
# WebMock. Só o MODELO é dublado: ele devolve a chamada de função, que é a decisão que a instrução
# §7.1 pede. O que este spec afirma é o que o CÓDIGO garante — o que chega ao modelo e o que fica no
# banco. A frase final ao cliente é do modelo, e não se prova por máquina.
#
# PROVA POR MUTAÇÃO (12/09/2026): a consulta abrindo um `ToolRun` por dentro, ou chamando
# `quote_start`, reprova os exemplos dos termos 2 e 5.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true,
                                            'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agente) do
    Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia',
                                                  nome_corretora: 'Seguros do Vale').call
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  # A mensagem do cliente que abre ESTE turno — outra que a que disparou a cotação (77).
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                           origin_message_id: 78)
  end
  let(:runs) { Autonomia::Agents::ToolRun.for_conversation(conversation.id) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:url) { 'https://agent.autonomia.site/query' }
  let(:trecho) { 'A assistência 24 horas inclui reboque até 200 km do local do evento.' }
  let(:duvida) { 'a assistência 24h da Porto cobre guincho?' }
  let(:chamada_da_cg) do
    { 'name' => 'consultar_condicoes_gerais', 'call_id' => 'cg1',
      'arguments' => { 'seguradora' => 'Porto', 'pergunta' => 'A assistência 24h cobre guincho?',
                       'ramo' => 'Automóvel' }.to_json }
  end
  # A resposta do modelo depois da rodada de ferramentas. O conteúdo dela não prova nada aqui: quem
  # escreve a frase ao cliente é o modelo.
  let(:resposta_do_modelo) do
    { reply: 'A assistência da Porto Seguro cobre reboque. Sigo com os preços.', confidence: 0.9,
      should_handoff: false, handoff_reason: nil, used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    # A corretora está conectada: a cotação PODE ser refeita neste turno. É isso que dá sentido a
    # provar que ela não foi.
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    conexao.update!(status: 'ready')
    conexao.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    # Sem base de conhecimento: o retrieval não é o assunto deste spec e chamaria embedding.
    agente.update!(config: agente.config.merge('with_knowledge' => false))
  end

  # O espião do portal: `quote_start` é a única chamada que custa dinheiro e deixa cotação no portal
  # do corretor (entrega 5). Nenhum turno de dúvida pode encostar nela.
  def espiar_portal
    connector = Autonomia::Insurance::Connector.client
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_start)
    connector
  end

  # A cotação que já está correndo: aberta numa mensagem anterior e promovida pelo Responder.
  def cotacao_correndo
    run = Autonomia::Agents::ToolRun.open!(
      agent: agente, slug: cotacao.slug, arguments: { 'produto' => 'auto', 'dados' => '{}' },
      scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id, origin_message_id: 77 }
    )
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.reload
  end

  def stub_da_cg(status:, grounded:, text: trecho, resolved: ['Porto Seguro'])
    body = { 'answer_text' => text, 'answer_status' => status, 'grounded' => grounded,
             'interpreted' => { 'insurers' => [{ 'sent' => 'Porto', 'resolved' => resolved,
                                                 'did_you_mean' => [] }] } }
    stub_request(:post, url).to_return(status: 200, body: body.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  # O modelo dublado: recebe o catálogo do turno e devolve a chamada de função que a §7.1 pede.
  def stub_do_modelo(function_call:)
    capturado = { tools: nil, outputs: nil }
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      capturado[:tools] = Array(kwargs[:tools])
      capturado[:outputs] = executor.call([function_call]) if executor
      { text: resposta_do_modelo }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    capturado
  end

  def responder
    described_class.new(agent: agente, query: duvida, trust_instruction: true, delivery: delivery).answer
  end

  def saida_da_ferramenta(capturado)
    capturado[:outputs].first[:output]
  end

  describe 'a dúvida é respondida pela cláusula (termo 1)' do
    it 'consulta as condições gerais e devolve ao modelo o trecho e a seguradora' do
      # Arrange
      cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      capturado = stub_do_modelo(function_call: chamada_da_cg)

      # Act
      responder

      # Assert — a consulta aconteceu, com a seguradora que o cliente citou
      expect(WebMock).to(have_requested(:post, url)
        .with { |req| JSON.parse(req.body)['insurer_name'] == 'Porto' })
      expect(saida_da_ferramenta(capturado)).to include('Porto Seguro', trecho)
    end

    it 'oferece a ferramenta ao principal no mesmo turno em que a cotação corre' do
      cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      capturado = stub_do_modelo(function_call: chamada_da_cg)

      responder

      expect(capturado[:tools].filter_map { |tool| tool[:name] }).to include('consultar_condicoes_gerais')
    end
  end

  describe 'a cotação em andamento não é tocada (termos 2 e 5)' do
    it 'a execução continua running, sem linha nova, sem superseded e sem chamar o portal' do
      # Arrange
      portal = espiar_portal
      run = cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      stub_do_modelo(function_call: chamada_da_cg)

      # Act
      responder

      # Assert — a linha sai do turno como entrou
      expect(run.reload.status).to eq('running')
      expect(runs.count).to eq(1)
      expect(runs.where(slug: cotacao.slug).count).to eq(1)
      expect(runs.where(status: 'superseded')).to be_empty
      expect(portal).not_to have_received(:quote_start)
    end

    it 'o turno da dúvida não aceita nenhuma execução' do
      cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      stub_do_modelo(function_call: chamada_da_cg)

      responder

      expect(delivery.runs).to be_empty
      expect(delivery).not_to be_any_runs
    end

    # A execução da cotação carrega a mensagem que a abriu. Se o turno da dúvida tivesse reaberto a
    # cotação, a linha viva seria outra — com a mensagem 78 no lugar da 77.
    it 'a execução viva continua sendo a que a mensagem anterior abriu' do
      run = cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      stub_do_modelo(function_call: chamada_da_cg)

      responder

      viva = runs.active.sole
      expect(viva.id).to eq(run.id)
      expect(viva.origin_message_id).to eq(77)
    end
  end

  # TERMO 4 — SEM CLÁUSULA, NÃO SE RESPONDE DE MEMÓRIA. `insufficient_context` sai da API com texto
  # plausível junto; o que o modelo recebe é a ordem de não usar esse texto.
  describe 'sem cláusula, o modelo é mandado não responder de memória (termo 4)' do
    it 'não repassa a prosa plausível e manda confirmar com um especialista' do
      # Arrange
      cotacao_correndo
      stub_da_cg(status: 'insufficient_context', grounded: false,
                 text: 'O contexto sugere que talvez o guincho esteja coberto.')
      capturado = stub_do_modelo(function_call: chamada_da_cg)

      # Act
      responder

      # Assert
      saida = saida_da_ferramenta(capturado)
      expect(saida).not_to include('talvez o guincho esteja coberto')
      expect(saida).to match(/NÃO responda de memória/i)
      expect(saida).to match(/confirmar com um especialista/i)
    end

    it 'a cotação segue correndo mesmo quando a dúvida não teve resposta' do
      portal = espiar_portal
      run = cotacao_correndo
      stub_da_cg(status: 'insufficient_context', grounded: false, text: 'Talvez.')
      stub_do_modelo(function_call: chamada_da_cg)

      responder

      expect(run.reload.status).to eq('running')
      expect(runs.count).to eq(1)
      expect(portal).not_to have_received(:quote_start)
    end
  end
end
