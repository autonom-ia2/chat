require 'rails_helper'

# A LIA VÊ O RESULTADO DA COTAÇÃO, PELO CAMINHO REAL (fatia 2 do #420).
#
# O agente é o que o `Builder` cria (principal + especialista de auto), o catálogo do turno é o do
# `Answerer`, o turno é o do `Operate::Responder`, e a publicação é a do motor (`AsyncRunJob`) e do
# publicador. Dublados: o modelo (devolve a chamada de função e a fala) e nada mais. Os dados são sintéticos.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agente) do
    Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 91)
  end
  let(:slug) { 'ver_resultado_da_cotacao' }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:ferramenta) { Autonomia::Agents::Tools::Native::InsuranceQuoteResult }
  let(:job) { Autonomia::Agents::Tools::AsyncRunJob }
  let(:porto) { cotou('8', 'Porto Seguro', 2119.18) }
  let(:allianz) { cotou('5', 'Allianz', 2402.55) }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    enable_test_encryption!
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    conexao.update!(status: 'ready')
    conexao.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    # Sem base de conhecimento: o retrieval não é o assunto deste spec e chamaria embedding.
    agente.update!(config: agente.config.merge('with_knowledge' => false))
  end

  def cotou(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def risco
    { 'kind' => 'risco', 'text' => 'Risco sem aceitação para este cenário nesta seguradora.' }
  end

  # A cotação da conversa, encerrada (ou no status pedido), com o resultado guardado destas ofertas; `handle`
  # substitui o handle inteiro.
  def cotacao_da_conversa(ofertas, status: 'done', criada: 5.minutes.ago, handle: nil)
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agente, slug: cotacao.slug, status: status, conversation_id: conversation.id,
      agent_inbox_id: agent_inbox.id, execution_key: SecureRandom.uuid, arguments: {}, created_at: criada,
      handle: handle || { 'quote_id' => 'q-1:1', cotacao::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) }
    )
  end

  def chamada(seguradora = nil, id = 'r1')
    { 'name' => slug, 'call_id' => id, 'arguments' => { 'seguradora' => seguradora }.to_json }
  end

  def fala(texto)
    { reply: texto, confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # O modelo dublado: recebe o catálogo e devolve as chamadas de função da rodada (uma, ou várias em
  # `chamadas`); `capturado` guarda o que ele recebeu.
  def modelo(function_call: nil, chamadas: nil, texto: 'Aqui estão as opções que chegaram.')
    capturado = { tools: nil, outputs: nil }
    lista = chamadas || [function_call].compact
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      capturado[:tools] = Array(kwargs[:tools]).filter_map { |tool| tool[:name] }
      capturado[:outputs] = executor.call(lista) if lista.any? && executor
      { text: fala(texto) }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    capturado
  end

  def responder
    described_class.new(agent: agente, query: 'quais preços chegaram?', trust_instruction: true, delivery: delivery).answer
  end

  def saida(capturado)
    capturado[:outputs].first[:output]
  end

  describe 'o catálogo do turno' do
    it 'a ferramenta é do principal, e o especialista não a recebe' do
      capturado = modelo

      responder

      expect(capturado[:tools]).to include(slug, 'consultar_condicoes_gerais')
      expect(capturado[:tools]).not_to include('cotar_seguro', 'consultar_placa')
      expect(agente.specialists.first.tools.map(&:slug)).to contain_exactly('consultar_placa', 'cotar_seguro')
    end

    # O AGENTE 24 EM PRODUÇÃO tem a lista gravada em 11/09/2026, sem a ferramenta nova. Ela chega pela lista
    # do deploy, e nada é escrito na linha do agente.
    it 'chega ao agente criado antes, com a lista antiga gravada, sem escrita no agente' do
      antiga = %w[consultar_produtos_cotacao consultar_condicoes_gerais cotar_seguro consultar_placa]
      agente.update!(config: agente.config.merge('native_tool_slugs' => antiga))
      config_antes = agente.reload.config
      capturado = modelo

      responder

      expect(capturado[:tools]).to include(slug)
      expect(agente.reload.config).to eq(config_antes)
    end

    # A RESERVA TAMBÉM É A DO DEPLOY: sem ela, a ferramenta que o especialista ganhou depois do nascimento
    # (em 11/09/2026 foi `consultar_placa`) apareceria para o principal enquanto a coluna não fosse escrita.
    it 'a ferramenta do especialista que falta na coluna dele continua reservada, e chega ao especialista' do
      especialista = agente.specialists.first
      especialista.update!(tool_slugs: ['cotar_seguro'])
      capturado = modelo

      responder

      expect(capturado[:tools]).not_to include('consultar_placa', 'cotar_seguro')
      expect(especialista.reload.tools.map(&:slug)).to contain_exactly('consultar_placa', 'cotar_seguro')
    end

    # COM O ESPECIALISTA DESLIGADO não há reserva: o principal recebe tudo, como já acontecia antes desta
    # fatia. A ferramenta nova continua do principal e lê a cotação da conversa do mesmo jeito.
    it 'com o especialista desligado, a Lia recebe também a de cotação, e a de resultado continua respondendo' do
      agente.specialists.first.update!(enabled: false)
      cotacao_da_conversa([porto])
      capturado = modelo(function_call: chamada)

      responder

      expect(capturado[:tools]).to include(slug, 'cotar_seguro', 'consultar_placa')
      expect(saida(capturado)).to include(ferramenta::LISTA_DEPOIS)
    end

    it 'agente comum sem o slug na config não recebe a ferramenta' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'Atenda.',
                                               config: { 'native_tool_slugs' => ['consultar_condicoes_gerais'] })

      expect(Autonomia::Agents::Tools::Registry.for_agent(comum).map(&:slug)).to eq(['consultar_condicoes_gerais'])
    end
  end

  describe 'o turno' do
    it 'com preço a mostrar: o modelo recebe o aceite sem valor, e a execução é aberta no turno' do
      cotacao_da_conversa([porto, allianz])
      capturado = modelo(function_call: chamada)

      responder

      expect(saida(capturado)).to start_with(ferramenta::LISTA_DEPOIS)
      expect(saida(capturado)).not_to match(/R\$|2119|2\.119|2402|2\.402/)
      expect(Autonomia::Agents::ToolRun.where(slug: slug).sole).to have_attributes(status: 'pending')
      expect(delivery.runs.map(&:slug)).to eq([slug])
    end

    # O ACEITE É O DA INSTÂNCIA (`Native::Base#aceite`), e não o texto fixo da classe: é por ele que o motivo
    # de uma seguradora chega ao modelo no mesmo pedido em que outra tem preço a publicar.
    it 'com preço de uma e motivo de outra: o aceite leva as duas falas, e a execução é aberta' do
      sancor = { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'declined', 'reason' => risco }
      cotacao_da_conversa([porto, sancor])
      capturado = modelo(function_call: chamada('Sancor e Porto'))

      responder

      expect(saida(capturado)).to include('Porto Seguro fez proposta', 'Sancor não fez proposta nesta cotação.', risco['text'])
      expect(saida(capturado)).not_to eq(ferramenta.accepted_message)
      expect(Autonomia::Agents::ToolRun.where(slug: slug).sole.arguments).to eq('seguradora' => 'Sancor e Porto')
    end

    it 'sem preço a mostrar: o modelo recebe o motivo liberado, e nenhuma execução é aberta' do
      cotacao_da_conversa([porto, { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'declined', 'reason' => risco }])
      capturado = modelo(function_call: chamada('Sancor'))

      responder

      expect(saida(capturado)).to include('Sancor não fez proposta nesta cotação.', risco['text'])
      expect(Autonomia::Agents::ToolRun.where(slug: slug)).to be_empty
    end

    # A MAIS NOVA É A RECUSA DO `start` (revisão da fatia 2, P3): o modelo não ouve "não ficou guardado, ofereça
    # um atendente", e sim que a última cotação não chegou às seguradoras.
    it 'a cotação mais nova recusada antes do portal: o modelo ouve que ela não chegou às seguradoras' do
      cotacao_da_conversa([porto], criada: 10.minutes.ago)
      cotacao_da_conversa([], criada: 1.minute.ago,
                              handle: { 'pedido' => 'Qual o ano do veículo?', 'motivo' => 'faltam_dados',
                                        Autonomia::Agents::ToolRun::SUBMITTED_KEY => true })
      capturado = modelo(function_call: chamada)

      responder

      expect(saida(capturado)).to eq(ferramenta::NAO_CHEGOU)
    end
  end

  describe 'do turno à publicação' do
    let(:user) { create(:user, account: account) }

    before do
      conversation.update!(assignee_agent_bot_id: agent_bot.id)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quais preços chegaram?')
    end

    def turno
      Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox,
                                                reply_to_message_id: conversation.messages.incoming.last.id).perform
    end

    def mensagens_do_bot
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
    end

    def execucao
      Autonomia::Agents::ToolRun.where(slug: slug, status: %w[pending running done failed]).sole
    end

    def itens(*ofertas)
      ofertas.map { |oferta| Autonomia::Insurance::QuoteOffers.item(oferta) }.join("\n\n")
    end

    def publicar(run)
      job.new.perform(run.id, 0)
      job.new.perform(run.id, 1)
    end

    def mensagem_do_cliente(texto)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
    end

    def exibicoes
      Autonomia::Agents::ToolRun.where(slug: slug).order(:id)
    end

    # A lista do turno 1 fica adiada, como fica enquanto a entrega humanizada da fala está em curso: a cadeia
    # ainda não postou o último pedaço. -> o `AsyncPublishJob` que ela enfileirou.
    def lista_adiada(run)
      run.update!(expected_chunks: 2)
      publicar(run)
      enqueued_jobs.find { |item| item[:job] == Autonomia::Agents::Tools::AsyncPublishJob && item[:args][0] == run.id }
    end

    # O teto de adiamentos da cadeia abortada (o cliente escreveu no meio): a publicação adiada tenta sem esperar.
    def publicar_no_teto(run, adiada)
      Autonomia::Agents::Tools::AsyncPublishJob.new.perform(run.id, adiada[:args][1], Autonomia::Agents::Tools::AsyncConfig::MAX_PUBLISH_DEFERRALS)
    end

    # DUAS CHAMADAS NA MESMA RODADA (revisão da fatia 2, P2): a segunda abertura supersede a primeira, e a
    # lista da primeira entra na da segunda.
    it 'duas chamadas da ferramenta na mesma rodada: a lista sai com as duas seguradoras' do
      cotacao_da_conversa([porto, allianz])
      modelo(chamadas: [chamada('Porto', 'r1'), chamada('Allianz', 'r2')], texto: 'Seguem as opções.')

      turno
      publicar(execucao)

      expect(Autonomia::Agents::ToolRun.where(slug: slug).order(:id).pluck(:status)).to eq(%w[superseded done])
      expect(mensagens_do_bot.map(&:content)).to eq(['Seguem as opções.', itens(porto, allianz)])
    end

    # O TURNO SEGUINTE CHEGA ANTES DE A LISTA DO ANTERIOR SAIR: a lista pendente entra na do pedido novo.
    it 'o pedido do turno seguinte, antes de a lista anterior sair, publica as duas' do
      cotacao_da_conversa([porto, allianz])
      modelo(function_call: chamada('Porto'), texto: 'A da Porto vem aqui.')
      turno
      mensagem_do_cliente('e a Allianz?')
      modelo(function_call: chamada('Allianz'), texto: 'E a da Allianz também.')

      turno
      publicar(execucao)

      expect(mensagens_do_bot.map(&:content)).to eq(['A da Porto vem aqui.', 'E a da Allianz também.', itens(porto, allianz)])
    end

    # A LISTA ADIADA E O "CADÊ?" (terceira rodada de revisão, P2): a execução do turno 1 fechou `done` com a
    # lista adiada; o pedido do turno 2 a leva, e a adiada não sai mais.
    it 'a lista adiada do turno anterior e o pedido de novo: a lista sai uma vez' do
      cotacao_da_conversa([porto, allianz])
      modelo(function_call: chamada, texto: 'Seguem os preços.')
      turno
      anterior = exibicoes.sole
      adiada = lista_adiada(anterior)
      expect(anterior.reload).to have_attributes(status: 'done', delivered_count: 1, sequence: 0)

      mensagem_do_cliente('cadê os preços?')
      modelo(function_call: chamada, texto: 'Aqui estão os preços.')
      turno
      publicar(exibicoes.last)
      publicar_no_teto(anterior, adiada)

      expect(mensagens_do_bot.map(&:content)).to eq(['Seguem os preços.', 'Aqui estão os preços.', itens(porto, allianz)])
    end

    it 'a lista adiada do turno anterior e o pedido por uma seguradora: o que foi prometido sai uma vez' do
      cotacao_da_conversa([porto, allianz])
      modelo(function_call: chamada, texto: 'Seguem os preços.')
      turno
      anterior = exibicoes.sole
      adiada = lista_adiada(anterior)

      mensagem_do_cliente('e a Porto?')
      modelo(function_call: chamada('Porto'), texto: 'A Porto fez proposta.')
      turno
      publicar(exibicoes.last)
      publicar_no_teto(anterior, adiada)

      expect(mensagens_do_bot.map(&:content)).to eq(['Seguem os preços.', 'A Porto fez proposta.', itens(porto, allianz)])
    end

    # A LISTA QUE VIROU MENSAGEM E NÃO FOI CONTADA (o processo morreu entre a mensagem e o `record_delivery!`):
    # o pedido seguinte não a repete.
    it 'a lista anterior que virou mensagem sem ser contada não entra de novo na do pedido seguinte' do
      cotacao_da_conversa([porto, allianz])
      modelo(function_call: chamada('Porto'), texto: 'A da Porto vem aqui.')
      turno
      anterior = exibicoes.sole
      job.new.perform(anterior.id, 0)
      lista = ferramenta.new(agent: agente, params: anterior.arguments, run: anterior.reload)
                        .poll(handle: anterior.handle.except(Autonomia::Agents::ToolRun::SUBMITTED_KEY)).deliveries.first
      Autonomia::Agents::Tools::AsyncPublisher.new(run: anterior).publish(lista)
      expect(anterior.reload).to have_attributes(status: 'running', delivered_count: 0, sequence: 1)

      mensagem_do_cliente('e a Allianz?')
      modelo(function_call: chamada('Allianz'), texto: 'E a da Allianz também.')
      turno
      publicar(exibicoes.last)
      job.new.perform(anterior.id, 1)

      expect(mensagens_do_bot.map(&:content)).to eq(['A da Porto vem aqui.', itens(porto), 'E a da Allianz também.', itens(allianz)])
    end

    # O QUE A LIA LEU É O QUE SAI (revisão da fatia 2, P2): a Sancor cotou entre a fala e a primeira passada, e a
    # lista não a traz, porque a Lia disse que ela ainda não tinha respondido.
    it 'a seguradora que cota entre a fala e a publicação não entra na lista anunciada' do
      fonte = cotacao_da_conversa([porto, { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'running' }],
                                  status: 'running')
      capturado = modelo(function_call: chamada('Porto e Sancor'), texto: 'A da Porto vem aqui.')
      turno
      depois = Autonomia::Insurance::ResultadoPorSeguradora.unir(fonte.handle[cotacao::RESULTADO_KEY], [cotou('19', 'Sancor', 1800.0)])
      fonte.update!(handle: fonte.handle.merge(cotacao::RESULTADO_KEY => depois))

      publicar(execucao)

      expect(saida(capturado)).to include('Sancor ainda não respondeu')
      expect(mensagens_do_bot.map(&:content)).to eq(['A da Porto vem aqui.', itens(porto)])
    end

    it 'a fala da Lia sai primeiro, e os itens de preço saem depois, escritos pelo código' do
      cotacao_da_conversa([porto, allianz])
      modelo(function_call: chamada, texto: 'Aqui estão as opções que chegaram.')

      turno
      job.new.perform(execucao.id, 0)
      job.new.perform(execucao.id, 1)

      expect(mensagens_do_bot.map(&:content)).to eq(['Aqui estão as opções que chegaram.', itens(porto, allianz)])
      expect(execucao.reload.status).to eq('done')
    end

    # NOTA PRIVADA: com um responsável humano na conversa, a Lia não responde, e a ferramenta nem chega a
    # ser oferecida ao modelo.
    it 'com responsável humano, a Lia não responde e a ferramenta não roda' do
      cotacao_da_conversa([porto])
      conversation.update!(assignee: user)
      capturado = modelo(function_call: chamada)

      resultado = turno

      expect(resultado.status).to eq(:silenced)
      expect(capturado[:tools]).to be_nil
      expect(Autonomia::Agents::ToolRun.where(slug: slug)).to be_empty
    end

    it 'o humano que assume entre a fala e a publicação recebe os itens em nota privada' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada)
      turno
      job.new.perform(execucao.id, 0)
      conversation.update!(assignee: user)

      job.new.perform(execucao.id, 1)

      expect(mensagens_do_bot.last).to have_attributes(content: itens(porto), private: true)
    end

    # RECONFERE NA PUBLICAÇÃO: a publicação adiada (a fala do turno ainda saindo) que chega depois de o
    # cliente abrir uma cotação nova não publica os preços da anterior.
    it 'a publicação adiada não sai quando outra cotação ficou mais nova, e sai quando não' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada)
      turno
      run = execucao
      run.update!(expected_chunks: 2)
      job.new.perform(run.id, 0)
      job.new.perform(run.id, 1)
      adiada = enqueued_jobs.find { |item| item[:job] == Autonomia::Agents::Tools::AsyncPublishJob }
      forcar = Autonomia::Agents::Tools::AsyncConfig::MAX_PUBLISH_DEFERRALS

      cotacao_da_conversa([allianz], status: 'running', criada: 1.second.from_now)
      Autonomia::Agents::Tools::AsyncPublishJob.new.perform(run.id, adiada[:args][1], forcar)
      expect(mensagens_do_bot.map(&:content)).not_to include(itens(porto), itens(allianz))

      Autonomia::Agents::ToolRun.where(slug: cotacao.slug, status: 'running').find_each { |nova| nova.update!(status: 'superseded') }
      Autonomia::Agents::Tools::AsyncPublishJob.new.perform(run.id, adiada[:args][1], forcar)
      expect(mensagens_do_bot.map(&:content)).to include(itens(porto))
    end

    # NENHUMA FRASE PRONTA: nem o aviso de espera do turno mudo, nem a frase de falha do prazo.
    it 'o turno mudo e o prazo esgotado não publicam frase nenhuma da ferramenta' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada, texto: Autonomia::Agents::Operate::Responder::SILENCE_TOKEN)
      turno
      run = execucao
      expect(run.notify_customer).to be(true)

      job.new.perform(run.id, 0)
      run.update!(expires_at: 1.minute.ago)
      job.new.perform(run.id, 1)

      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(mensagens_do_bot).to be_empty
    end
  end
end
