require 'rails_helper'

# A LIA ESCREVE OS PREÇOS QUE O ESPECIALISTA LEU, PELO CAMINHO REAL (fatias 2 e 3 do #420; chat#585).
#
# O agente é o que o `Builder` cria (principal + especialista de auto), o catálogo do turno é o do `Answerer`, o turno
# é o do `Operate::Responder`. Desde a #585 a ferramenta de resultado é do ESPECIALISTA (decisão do CEO em 22/09/2026):
# a Lia consulta o especialista, ele lê o resultado com a ferramenta real, e o que ela devolveu fica no MESMO turno —
# é por isso que a conferência da fala da Lia (`ConferenciaDePrecos`) continua valendo. Dublados: o modelo dos dois
# (a Lia chama o especialista; o especialista chama a ferramenta e repassa o que leu; a fala e, quando pedida, a
# reescrita) e nada mais. Os dados são sintéticos.
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
  let(:porto) { cotou('8', 'Porto Seguro', 2119.18) }
  let(:allianz) { cotou('5', 'Allianz', 2402.55) }
  let(:mensal) do
    { 'insurer' => { 'code' => '55', 'name' => 'Bp Assinatura' }, 'status' => 'quoted',
      'premium' => { 'amount' => 298.43, 'currency' => 'BRL', 'basis' => 'monthly' } }
  end

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

  # Um motivo de risco que o molde do veículo aceita (`Insurance::MotivoDaRecusa`).
  def risco
    { 'kind' => 'risco', 'text' => 'Tipo de veículo não aceito.' }
  end

  def sancor(reason = risco)
    { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'declined', 'reason' => reason }
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

  # Os modelos dublados, separados pelo esquema da resposta: o ESPECIALISTA (`Runner::RESULT_SCHEMA`) recebe o
  # catálogo dele, executa as chamadas da rodada (uma, ou várias em `chamadas`) e repassa o que leu; a LIA recebe o
  # catálogo dela e, havendo chamadas, consulta o especialista. `capturado` guarda o que cada um recebeu, e
  # `outputs` é o que a ferramenta devolveu ao especialista.
  # `reescrita`: o Hash que o modelo devolve quando a conferência pede a reescrita, ou a exceção da chamada.
  def modelo(function_call: nil, chamadas: nil, texto: 'Aqui estão as opções que chegaram.', reescrita: nil)
    capturado = { tools: nil, tools_do_especialista: nil, outputs: nil, reescritas: [] }
    lista = chamadas || [function_call].compact
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      nomes = Array(kwargs[:tools]).filter_map { |tool| tool[:name] }
      next especialista(capturado, nomes, lista, executor) if do_especialista?(kwargs)

      lia(capturado, nomes, lista, executor)
      { text: fala(texto) }
    end
    dublar_reescrita(client, capturado, reescrita)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    capturado
  end

  def do_especialista?(kwargs)
    kwargs.dig(:schema, :name) == Autonomia::Agents::Specialists::Runner::RESULT_SCHEMA[:name]
  end

  def lia(capturado, nomes, lista, executor)
    capturado[:tools] = nomes
    return unless lista.any? && executor

    consulta = consulta_ao_especialista
    # Sem o especialista (desligado), a Lia tem a ferramenta e a chama direto.
    nomes.include?(consulta['name']) ? executor.call([consulta]) : capturado[:outputs] = executor.call(lista)
  end

  def especialista(capturado, nomes, lista, executor)
    capturado[:tools_do_especialista] = nomes
    capturado[:outputs] = executor.call(lista) if lista.any? && executor
    { text: { resposta: Array(capturado[:outputs]).pluck(:output).join("\n"), dados_faltando: [] }.to_json }
  end

  def consulta_ao_especialista
    { 'name' => agente.specialists.first.function_name, 'call_id' => 'e1',
      'arguments' => { Autonomia::Agents::Specialist::REQUEST_PARAM => 'o cliente quer ver os preços da cotação' }.to_json }
  end

  # A chamada de reescrita que a conferência de preços faz (`ResponsesClient#create`).
  def dublar_reescrita(client, capturado, reescrita)
    allow(client).to receive(:create) do |**kwargs|
      capturado[:reescritas] << kwargs
      raise reescrita if reescrita.is_a?(Class)

      { text: reescrita.to_json }
    end
  end

  def responder
    described_class.new(agent: agente, query: 'quais preços chegaram?', trust_instruction: true, delivery: delivery).answer
  end

  def saida(capturado)
    capturado[:outputs].first[:output]
  end

  # A linha que o modelo lê de uma seguradora com preço.
  def preco(oferta)
    premio = Autonomia::Insurance::PremiumText.new(oferta['premium'])
    "#{oferta.dig('insurer', 'name')} fez proposta: #{[premio.resumo, premio.detalhe].compact.join(', ')}."
  end

  describe 'o catálogo do turno' do
    it 'a ferramenta é do especialista, e a Lia não a recebe' do
      capturado = modelo(function_call: chamada)

      responder

      expect(capturado[:tools]).to include('consultar_condicoes_gerais', 'enviar_proposta_da_seguradora')
      expect(capturado[:tools]).not_to include(slug, 'cotar_seguro', 'consultar_placa')
      expect(capturado[:tools_do_especialista]).to include(slug)
      expect(agente.specialists.first.tools.map(&:slug)).to contain_exactly('consultar_placa', 'cotar_seguro', slug)
    end

    # O AGENTE 24 EM PRODUÇÃO tem a lista gravada em 11/09/2026, sem a ferramenta nova. Ela chega pela lista
    # do deploy, e nada é escrito na linha do agente.
    it 'chega ao agente criado antes, com a lista antiga gravada, sem escrita no agente' do
      antiga = %w[consultar_produtos_cotacao consultar_condicoes_gerais cotar_seguro consultar_placa]
      agente.update!(config: agente.config.merge('native_tool_slugs' => antiga))
      config_antes = agente.reload.config
      capturado = modelo(function_call: chamada)

      responder

      expect(capturado[:tools_do_especialista]).to include(slug)
      expect(agente.reload.config).to eq(config_antes)
    end

    # A RESERVA TAMBÉM É A DO DEPLOY: sem ela, a ferramenta que o especialista ganhou depois do nascimento
    # (em 11/09/2026 foi `consultar_placa`) apareceria para o principal enquanto a coluna não fosse escrita.
    it 'a ferramenta do especialista que falta na coluna dele continua reservada, e chega ao especialista' do
      especialista = agente.specialists.first
      especialista.update!(tool_slugs: ['cotar_seguro'])
      capturado = modelo

      responder

      expect(capturado[:tools]).not_to include('consultar_placa', 'cotar_seguro', slug)
      expect(especialista.reload.tools.map(&:slug)).to contain_exactly('consultar_placa', 'cotar_seguro', slug)
    end

    # COM O ESPECIALISTA DESLIGADO não há reserva: o principal recebe tudo, como já acontecia antes desta
    # fatia. A ferramenta nova continua do principal e lê a cotação da conversa do mesmo jeito.
    it 'com o especialista desligado, a Lia recebe também a de cotação, e a de resultado continua respondendo' do
      agente.specialists.first.update!(enabled: false)
      cotacao_da_conversa([porto])
      capturado = modelo(function_call: chamada)

      responder

      expect(capturado[:tools]).to include(slug, 'cotar_seguro', 'consultar_placa')
      expect(saida(capturado)).to include(preco(porto))
    end

    it 'agente comum sem o slug na config não recebe a ferramenta' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'Atenda.',
                                               config: { 'native_tool_slugs' => ['consultar_condicoes_gerais'] })

      expect(Autonomia::Agents::Tools::Registry.for_agent(comum).map(&:slug)).to eq(['consultar_condicoes_gerais'])
    end
  end

  describe 'o turno' do
    it 'com preço a mostrar: o modelo recebe os preços com o período, o turno os registra, e nenhuma execução abre' do
      cotacao_da_conversa([porto, allianz])
      capturado = modelo(function_call: chamada)

      responder

      expect(saida(capturado)).to include('2 seguradoras fizeram proposta nesta cotação.', preco(porto), preco(allianz),
                                          ferramenta::COMO_ESCREVER)
      expect(delivery.resultado_do_turno.texto).to eq(saida(capturado))
      expect(Autonomia::Agents::ToolRun.where(slug: slug)).to be_empty
    end

    it 'com preço de uma e motivo de outra: as duas falas, com a categoria e sem o texto do portal' do
      cotacao_da_conversa([porto, sancor])
      capturado = modelo(function_call: chamada('Sancor e Porto'))

      responder

      expect(saida(capturado)).to include('Porto Seguro fez proposta', 'Sancor não fez proposta nesta cotação.',
                                          ferramenta::MOTIVOS.fetch('veiculo'))
      expect(saida(capturado)).not_to include(risco['text'])
      expect(saida(capturado)).to include(preco(porto))
    end

    it 'sem preço a mostrar: o modelo recebe a categoria do motivo, e nenhum valor' do
      cotacao_da_conversa([porto, sancor])
      capturado = modelo(function_call: chamada('Sancor'))

      responder

      expect(saida(capturado)).to end_with("Sancor não fez proposta nesta cotação. #{ferramenta::MOTIVOS.fetch('veiculo')}")
      expect(Autonomia::Agents::ConferenciaDePrecos.valores(saida(capturado))).to be_empty
    end

    # A CONTA DA CORRETORA E O DADO DA PESSOA NÃO VIRAM CATEGORIA: pelo caminho real, o modelo ouve só que a seguradora
    # não fez proposta.
    it 'motivo com a conta da corretora ou com o dado da pessoa: o modelo ouve só que ela não fez proposta' do
      ['Tipo de veículo sem aceitação para o seu código.', 'Negativado: CEP sem aceitação.'].each do |texto|
        Autonomia::Agents::ToolRun.where(slug: cotacao.slug).delete_all
        cotacao_da_conversa([porto, sancor('kind' => 'risco', 'text' => texto)])
        capturado = modelo(function_call: chamada('Sancor'))

        responder

        expect(saida(capturado)).to end_with("Sancor não fez proposta nesta cotação. #{ferramenta::SEM_MOTIVO}")
      end
    end

    # A MAIS NOVA É A RECUSA DO `start`: o modelo ouve que a última cotação não chegou às seguradoras.
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

  describe 'do turno à entrega' do
    let(:user) { create(:user, account: account) }

    before do
      conversation.update!(assignee_agent_bot_id: agent_bot.id)
      mensagem_do_cliente('quais preços chegaram?')
    end

    def turno
      Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox,
                                                reply_to_message_id: conversation.messages.incoming.last.id).perform
    end

    def mensagens_do_bot
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
    end

    def mensagem_do_cliente(texto)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
    end

    # O CASO DA PROVA REAL DE 18/09/2026: o cliente pediu só as três mais baratas e recebeu onze, porque a lista era
    # do código. Agora a Lia escreve o recorte, com valor e nome conferidos, e é só isso que sai.
    it 'o cliente pede so as tres mais baratas: sai uma mensagem, com tres seguradoras e valores conferidos' do
      cotacao_da_conversa([porto, allianz, cotou('3', 'Mapfre', 2582.76), cotou('11', 'Tokio Marine', 1999.9), mensal])
      fala = 'As três mais baratas no total são a *Tokio Marine*, *R$ 1.999,90* no total; a *Porto Seguro*, ' \
             '*R$ 2.119,18* no total; e a *Allianz*, *R$ 2.402,55* no total.'
      capturado = modelo(function_call: chamada, texto: fala)

      turno

      expect(mensagens_do_bot.map(&:content)).to eq([fala])
      expect(fala.scan('R$').size).to eq(3)
      expect(fala).not_to include('Mapfre', 'Bp Assinatura')
      expect(capturado[:reescritas]).to be_empty
    end

    it 'o valor inventado volta ao modelo uma vez, e sai a reescrita conferida' do
      cotacao_da_conversa([porto, allianz])
      certa = 'A mais barata é a *Porto Seguro*: *R$ 2.119,18* no total.'
      capturado = modelo(function_call: chamada, texto: 'A mais barata é a Porto Seguro: R$ 1.999,00 no total.',
                         reescrita: { 'reply' => certa, 'reply_sem_valores' => 'Os valores estão no comparativo.' })

      turno

      expect(mensagens_do_bot.map(&:content)).to eq([certa])
      expect(capturado[:reescritas].size).to eq(1)
      expect(capturado[:reescritas].first[:schema]).to eq(Autonomia::Agents::ConferenciaDePrecos::REESCRITA)
      expect(capturado[:reescritas].first[:input].last[:content].first[:text]).to include(preco(porto))
    end

    it 'a reescrita que ainda inventa: sai a versão sem valores' do
      cotacao_da_conversa([porto])
      sem_valores = 'Os valores de cada seguradora estão no comparativo que te mandei.'
      modelo(function_call: chamada, texto: 'Porto Seguro: R$ 1.999,00.',
             reescrita: { 'reply' => 'Porto Seguro: R$ 1.998,00.', 'reply_sem_valores' => sem_valores })

      turno

      expect(mensagens_do_bot.map(&:content)).to eq([sem_valores])
    end

    it 'a reescrita que falha: sai o recuo, e nunca o valor inventado' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada, texto: 'Porto Seguro: R$ 1.999,00.', reescrita: Crm::Ai::ResponsesClient::Error)

      turno

      expect(mensagens_do_bot.map(&:content)).to eq([Autonomia::Agents::ConferenciaDePrecos::RECUO_SEM_COMPARATIVO])
    end

    it 'com a entrega humanizada, a cadeia leva só a fala da Lia' do
      with_modified_env(AI_HUMANIZE_DELIVERY: 'true') do
        cotacao_da_conversa([porto, allianz])
        fala = 'A Porto Seguro ficou em R$ 2.119,18 no total.'
        modelo(function_call: chamada, texto: fala)

        turno

        cadeia = enqueued_jobs.find { |item| item[:job] == Autonomia::Agents::Operate::ChunkedDeliveryJob }
        chunks = ActiveJob::Arguments.deserialize(cadeia[:args])[3]
        expect(chunks.map { |chunk| chunk['text'] }.join(' ')).to eq(fala)
      end
    end

    it 'o retry do ReplyJob não repete a fala' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada, texto: 'A Porto Seguro ficou em R$ 2.119,18 no total.')

      2.times { turno }

      expect(mensagens_do_bot.map(&:content)).to eq(['A Porto Seguro ficou em R$ 2.119,18 no total.'])
    end

    # O TURNO MUDO: a Lia decidiu calar, e o código não fala por ela.
    it 'o turno mudo: nada sai' do
      cotacao_da_conversa([porto])
      modelo(function_call: chamada, texto: Autonomia::Agents::Operate::Responder::SILENCE_TOKEN)

      resultado = turno

      expect(resultado.status).to eq(:silenced)
      expect(mensagens_do_bot).to be_empty
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
      expect(mensagens_do_bot).to be_empty
    end
  end
end
