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

  # A cotação ACEITA no turno anterior e ainda não despachada: `pending`, que é como `ToolRun.open!`
  # cria. Este é o estado frágil — `pending` é aceitação que ainda não virou trabalho, e é o estado
  # que o `discard!` e a abertura de um pedido novo podem varrer.
  def cotacao_aceita
    Autonomia::Agents::ToolRun.open!(
      agent: agente, slug: cotacao.slug, arguments: { 'produto' => 'auto', 'dados' => '{}' },
      scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id, origin_message_id: 77 }
    )
  end

  # A cotação que já está correndo: aberta numa mensagem anterior e promovida pelo Responder.
  def cotacao_correndo
    run = cotacao_aceita
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

  # O modelo dublado: recebe o catálogo do turno e devolve a chamada de função que a §7.1 pede. Sem
  # `function_call` ele só devolve a resposta — serve para olhar o catálogo, sem executar nada.
  def stub_do_modelo(function_call: nil)
    capturado = { tools: nil, outputs: nil }
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      capturado[:tools] = Array(kwargs[:tools])
      capturado[:outputs] = executor.call([function_call]) if function_call && executor
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

  # TERMO 1, PARCIAL — O QUE SE PROVA AQUI É O CONTRATO FERRAMENTA→MODELO. O termo diz "a dúvida é
  # respondida com a cláusula, dizendo de qual seguradora é": a frase que o CLIENTE lê é escrita pelo
  # modelo, e aqui o modelo é dublado — o dublê responde "cobre reboque" independentemente do que a
  # ferramenta devolveu. O que a máquina prova é o insumo: a consulta foi feita com a seguradora que
  # o cliente citou, e o trecho e o nome da seguradora chegaram ao modelo. A conduta fecha na prova
  # real (§7 da auditoria).
  describe 'o que chega ao modelo na dúvida — contrato ferramenta→modelo (termo 1, parcial)' do
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

  # TERMOS 2 E 5 — invariante de código, e só dele: executar SOMENTE a consulta preserva a execução
  # viva. Que o modelo chame só a consulta (e não também o especialista, que reabriria a cotação) é
  # conduta dele, e se prova na conversa real.
  describe 'executar só a consulta não toca na cotação em andamento (termos 2 e 5)' do
    it 'a execução running continua running, sem linha nova, sem superseded e sem chamar o portal' do
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

    # O ESTADO FRÁGIL: a cotação foi ACEITA no turno anterior e ainda não foi despachada (`pending`).
    # `pending` não é protegida como `running` — ela não conta para `possivelmente_duplicada?`, e é o
    # estado que um pedido novo varre (`ToolRun.open!` supersedia TODA execução ativa, pending
    # inclusive). Se o turno da dúvida abrisse qualquer execução, é esta linha que morreria primeiro,
    # e a cotação aceita nunca chegaria ao portal.
    it 'a execução aceita e ainda não despachada continua pending' do
      portal = espiar_portal
      run = cotacao_aceita
      stub_da_cg(status: 'answered', grounded: true)
      stub_do_modelo(function_call: chamada_da_cg)

      responder

      expect(run.reload.status).to eq('pending')
      expect(runs.count).to eq(1)
      expect(runs.where(status: 'superseded')).to be_empty
      expect(portal).not_to have_received(:quote_start)
    end

    # ISTO OLHA SÓ A MEMÓRIA DO TURNO, não o banco: `Delivery#runs` é a lista que `accept_async`
    # preenche, e é ela que o `Responder` consulta no fim do turno para promover e despachar. Vazia
    # quer dizer que o turno não tem nada a despachar — uma mutação que abrisse `ToolRun` por fora do
    # `Delivery` passaria por aqui (e foi o que aconteceu em 12/09/2026). Quem conta linha no banco
    # são os exemplos acima.
    it 'o contexto de entrega do turno sai sem execução aceita — nada a despachar' do
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

  # TERMO 4, PARCIAL — TAMBÉM É CONTRATO FERRAMENTA→MODELO. `insufficient_context` sai da API com
  # texto plausível junto; o que a ferramenta entrega ao modelo é a ordem de NÃO usar esse texto. Se
  # o modelo obedece é outra coisa: o dublê deste arquivo responde "cobre reboque" mesmo com
  # `insufficient_context`, e passa — porque a frase ao cliente não é o que este exemplo mede. A
  # obediência fecha na prova real (§7 da auditoria, item 9).
  describe 'sem cláusula, a ferramenta manda o modelo não responder de memória (termo 4, parcial)' do
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

  # A TERCEIRA FONTE QUE NÃO PODE EXISTIR (termo 4). "Sem cláusula, diga que não achou" só é uma
  # ordem cumprível se a cláusula for a ÚNICA fonte possível para cobertura. `web_search` é a busca
  # nativa da Responses API, entra no catálogo de todo agente por padrão (`Answerer#answer_tools`), e
  # responderia a mesma pergunta com texto de internet — sem cláusula, sem seguradora e sem SUSEP.
  # Ela sai do catálogo do agente de cotação, e só dele.
  describe 'a busca web não é oferecida ao agente de cotação' do
    around do |example|
      with_modified_env(AI_WEB_SEARCH_ENABLED: 'true') { example.run }
    end

    it 'o turno da dúvida não tem web_search no catálogo, e tem a consulta às condições gerais' do
      cotacao_correndo
      stub_da_cg(status: 'answered', grounded: true)
      capturado = stub_do_modelo(function_call: chamada_da_cg)

      responder

      expect(capturado[:tools].map { |tool| tool[:type] }).not_to include('web_search')
      expect(capturado[:tools].filter_map { |tool| tool[:name] }).to include('consultar_condicoes_gerais')
    end

    # O CONTRASTE QUE IMPEDE A REGRESSÃO DOS OUTROS AGENTES: mesma conta, mesmo dublê, mesmo turno —
    # quem não é agente de cotação continua com a busca. Sem este exemplo, desligar a busca para
    # todo mundo passaria.
    it 'um agente comum da mesma conta continua recebendo web_search' do
      comum = Autonomia::Agents::Agent.create!(
        account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
        instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false }
      )
      capturado = stub_do_modelo

      described_class.new(agent: comum, query: duvida, trust_instruction: true).answer

      expect(capturado[:tools].map { |tool| tool[:type] }).to include('web_search')
    end
  end
end
