require 'rails_helper'

# A COTAÇÃO FECHA SEM ESPERAR O PORTAL (fatia 1 do PDF rápido, 13/09/2026) — pelo motor.
#
# O defeito, medido no portal real: com qualquer seguradora recusando, o adapter nunca devolve
# `completed`, e a execução só acabava no prazo (`fail_run('prazo_esgotado')`), com o PDF junto — as
# quatro cotações reais de 12/09 terminaram assim. Todas as seguradoras tinham desfecho em 41 s, 98 s
# e 64 s.
#
# Estes exemplos rodam o motor de verdade sobre a ferramenta de cotação de verdade, com o conector
# `mock` respondendo, passada a passada, a FORMA que o portal real respondeu (dados sintéticos), o
# publicador de verdade e o download do PDF pelo WebMock. O que se lê é a conversa, como o cliente a
# leria, e a linha da execução, como os leitores de status a leem.
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
  # A URL que o conector `mock` devolve para o comparativo.
  let(:url) { 'https://exemplo.test/comparativo-mock.pdf' }
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }
  let(:portal_fora) { Autonomia::Insurance::Connector::Error.new(:timeout, 'connector timeout em /v1/agger/quote/proposal') }

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
    # O `SafeFetch` resolve o nome antes de conectar: o host de teste ganha um endereço público.
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
  end

  def oferta(code, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    return base unless amount

    base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' })
  end

  # AS TRÊS LEITURAS DO PORTAL, na forma da medição de 13/09/2026 em miniatura: todas as seguradoras
  # listadas desde a primeira; preço e recusa chegando aos poucos; e, na terceira, toda seguradora com
  # desfecho enquanto o portal ainda diz `partial`.
  def leitura_inicial
    %w[8 20 47 11 19].map { |codigo| oferta(codigo, 'running') }
  end

  def leitura_parcial
    [oferta('8', 'quoted', 2119.18), oferta('20', 'quoted', 2323.17), oferta('47', 'declined'),
     oferta('11', 'auth_required'), oferta('19', 'running')]
  end

  def leitura_com_todas_com_desfecho
    leitura_parcial.first(4) + [oferta('19', 'declined')]
  end

  def portal_responde(status, ofertas)
    allow(mock).to receive(:quote_result).and_return({ 'quote_id' => 'q-1:1', 'status' => status, 'offers' => ofertas })
  end

  def pdf_responde(*respostas)
    stub_request(:get, url).to_return(*respostas)
  end

  def pdf_ok
    { status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' } }
  end

  def pdf_nao_encontrado
    { status: 404, body: '<Error><Code>BlobNotFound</Code></Error>', headers: { 'Content-Type' => 'application/xml' } }
  end

  # A execução como o motor a deixa depois da passada de submissão.
  def cotacao_submetida
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1',
                                  cotacao::DELIVERED_KEY => [], 'produto' => 'auto' })
    run
  end

  def passada(run, tentativa)
    described_class.new.perform(run.id, tentativa)
    run.reload
  end

  # As duas primeiras consultas: tudo `running`, depois dois preços e três ainda sem preço.
  def ate_a_leitura_parcial(run)
    portal_responde('running', leitura_inicial)
    passada(run, 1)
    portal_responde('partial', leitura_parcial)
    passada(run, 2)
  end

  def bot_messages
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  end

  def bot_contents
    bot_messages.map(&:content)
  end

  def precos
    bot_contents.first
  end

  def fecho
    cotacao::FECHO_COM_RESULTADO
  end

  it 'encerra quando toda seguradora tem desfecho, com o portal ainda partial: precos, comparativo, fecho e done' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    pdf_responde(pdf_ok)

    # Act — a terceira consulta: o portal continua `partial`
    portal_responde('partial', leitura_com_todas_com_desfecho)
    passada(run, 3)

    # Assert — a conversa
    expect(precos).to include('R$ 2.119,18', 'R$ 2.323,17')
    expect(bot_contents).to eq([precos, cotacao::Comparativo::LEGENDA, fecho])
    expect(bot_messages.second.attachments.sole.file.download).to eq(pdf)
    expect(bot_contents.join).not_to include(url)
    # Assert — a linha
    expect(run).to have_attributes(status: 'done', failure_code: nil, delivered_count: 2)
    expect(run.handle).to include(cotacao::FECHADO_KEY => true, cotacao::DELIVERED_KEY => %w[8 20])
  end

  # OS LEITORES DE STATUS. A linha deixa de acabar em `failed/prazo_esgotado` e passa a acabar em
  # `done`: o pedido repetido (24 h), o texto que o especialista lê nele e a medida do Super Admin
  # leem a mesma linha, e nenhum deles pode perder o que lia.
  it 'a linha done continua contando como pedido feito, com o texto de concluida, e a medida nao muda' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    pdf_responde(pdf_ok)
    portal_responde('partial', leitura_com_todas_com_desfecho)

    # Act
    passada(run, 3)

    # Assert
    expect(run.conta_como_pedido?).to be(true)
    expect(Autonomia::Agents::ToolRun.pedido_repetido(conversation.id, cotacao.slug, 'pedido-sintetico')).to eq(run)
    expect(Autonomia::Agents::Tools::PedidoRepetido.new(run).to_s)
      .to include('já terminou nesta conversa', '(concluída)', '2 resultados encaminhados para publicação')
    expect(Autonomia::Insurance::Medida.new(conta: account, inicio: nil, fim: nil).call)
      .to include(cotacoes: 1, seguradoras_acionadas: 5, seguradoras_com_preco: 2, cotacoes_sem_medida: 0)
  end

  it 'o comparativo que o portal nao gera na primeira vez sai na passada seguinte, com um fecho so' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    pdf_responde(pdf_ok)
    portal_responde('partial', leitura_com_todas_com_desfecho)
    allow(mock).to receive(:quote_proposal).and_raise(portal_fora)

    # Act 1 — o pedido de PDF volta 504
    passada(run, 3)

    # Assert 1 — nada novo na conversa, e a execução continua
    expect(bot_contents).to eq([precos])
    expect(run.status).to eq('running')
    expect(described_class).to have_been_enqueued.with(run.id, 4)

    # Act 2 — o portal responde
    allow(mock).to receive(:quote_proposal).and_call_original
    passada(run, 4)

    # Assert 2
    expect(bot_contents).to eq([precos, cotacao::Comparativo::LEGENDA, fecho])
    expect(run.status).to eq('done')
  end

  # O LINK DO PORTAL NÃO VAI MAIS AO CLIENTE (achado de segurança: sem assinatura, com o nome do
  # segurado no caminho, baixa sem autenticação). O download que falha é um PDF que não saiu: a
  # entrega não é aceita, a execução não encerra e a passada seguinte pede outro comparativo.
  it 'o download que falha nao manda o link: a passada seguinte gera o comparativo de novo' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    pdf_responde(pdf_nao_encontrado, pdf_ok)
    portal_responde('partial', leitura_com_todas_com_desfecho)

    # Act 1 — o download volta 404
    passada(run, 3)

    # Assert 1 — nenhuma mensagem nova, nenhum link, e a entrega não conta
    expect(bot_contents).to eq([precos])
    expect(run).to have_attributes(status: 'running', delivered_count: 1)
    expect(Autonomia::Agents::Tools::EntregaAceita.aceita?(run, run.handle[cotacao::COMPARATIVO_KEY])).to be(false)

    # Act 2
    passada(run, 4)

    # Assert 2 — o arquivo, o fecho, e o link em lugar nenhum
    expect(bot_contents).to eq([precos, cotacao::Comparativo::LEGENDA, fecho])
    expect(bot_contents.join).not_to include(url)
    expect(run.status).to eq('done')
    expect(mock).to have_received(:quote_proposal).twice
  end

  # CADA PEDIDO AO PORTAL DEVOLVE UMA URL DIFERENTE (medido em 13/09/2026). Com a fila recusando o envio
  # ao canal, o publicador deixa a mensagem do comparativo no banco com a pendência e devolve
  # `blocked`. A passada seguinte não pede outro comparativo — seria um segundo PDF, com outra URL —, e
  # o varredor retoma o envio pendente quando a fila volta.
  it 'o comparativo que ficou na conversa com o envio pendente nao vira um segundo PDF' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    outra_url = 'https://exemplo.test/comparativo-mock-2.pdf'
    allow(mock).to receive(:quote_proposal).and_return({ 'url' => url }, { 'url' => outra_url })
    pdf_responde(pdf_ok)
    stub_request(:get, outra_url).to_return(pdf_ok)
    portal_responde('partial', leitura_com_todas_com_desfecho)
    fila_recusa_o_envio

    # Act — a passada que cria a mensagem do PDF sem conseguir enfileirar o envio, e a seguinte
    passada(run, 3)
    expect(run.status).to eq('running')
    passada(run, 4)
    fila_volta
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert — um PDF só, o fecho, e um pedido só ao portal
    expect(bot_contents).to eq([precos, cotacao::Comparativo::LEGENDA, fecho])
    expect(bot_messages.flat_map(&:attachments).size).to eq(1)
    expect(mock).to have_received(:quote_proposal).once
    expect(run.reload.status).to eq('done')
  end

  describe 'esgotado o teto de tentativas do comparativo' do
    it 'com o portal sem gerar o PDF, conclui sem comparativo, sem link e com o fecho' do
      # Arrange
      run = cotacao_submetida
      ate_a_leitura_parcial(run)
      portal_responde('partial', leitura_com_todas_com_desfecho)
      allow(mock).to receive(:quote_proposal).and_raise(portal_fora)

      # Act
      [3, 4, 5].each { |tentativa| passada(run, tentativa) }

      # Assert
      expect(bot_contents).to eq([precos, fecho])
      expect(run.status).to eq('done')
      expect(mock).to have_received(:quote_proposal).exactly(3).times
    end

    it 'com o download sempre falhando, conclui sem comparativo, sem link e com o fecho' do
      # Arrange
      run = cotacao_submetida
      ate_a_leitura_parcial(run)
      portal_responde('partial', leitura_com_todas_com_desfecho)
      pdf_responde(pdf_nao_encontrado)

      # Act — três passadas recusam o arquivo; a quarta não pede mais
      [3, 4, 5, 6].each { |tentativa| passada(run, tentativa) }

      # Assert
      expect(bot_contents).to eq([precos, fecho])
      expect(bot_contents.join).not_to include(url)
      expect(run.status).to eq('done')
      expect(mock).to have_received(:quote_proposal).exactly(3).times
    end
  end

  # NUNCA DOIS DESFECHOS. O `done` pergunta à conversa por cada frase de fecho possível desta execução
  # (`Tools::Encerramento#fecho_publicado?`), como o encerramento já perguntava.
  describe 'o desfecho no caminho done' do
    it 'nao publica um segundo desfecho quando o fecho desta execucao ja esta na conversa' do
      # Arrange — o fecho já publicado por outra porta (o varredor cruzando com o motor)
      run = cotacao_submetida
      ate_a_leitura_parcial(run)
      pdf_responde(pdf_ok)
      Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(cotacao.closing_message(run.arguments))
      portal_responde('partial', leitura_com_todas_com_desfecho)

      # Act
      passada(run, 3)

      # Assert
      expect(bot_contents).to eq([precos, fecho, cotacao::Comparativo::LEGENDA])
      expect(run.status).to eq('done')
    end

    # A FRASE QUE UMA VERSÃO ANTERIOR PUBLICAVA também conta (`FRASES_DE_FECHO` guarda a constante
    # parcial para isso): a linha que atravessa o deploy não recebe o fecho novo ao lado do antigo.
    it 'nao publica o fecho novo ao lado da frase parcial que a versao anterior publicou' do
      run = cotacao_submetida
      ate_a_leitura_parcial(run)
      pdf_responde(pdf_ok)
      Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(cotacao::PARCIAL)
      portal_responde('partial', leitura_com_todas_com_desfecho)

      passada(run, 3)

      expect(bot_contents).to eq([precos, cotacao::PARCIAL, cotacao::Comparativo::LEGENDA])
    end

    # TODAS RECUSARAM: nenhum preço, nenhum comparativo, e a frase de falha — sem esperar o prazo.
    it 'com todas recusando, conclui com a frase de falha' do
      run = cotacao_submetida
      portal_responde('running', leitura_inicial)
      passada(run, 1)
      portal_responde('running', %w[8 20 47 11 19].map { |codigo| oferta(codigo, 'declined') })

      passada(run, 2)

      expect(bot_contents).to eq([cotacao.failure_message])
      expect(run).to have_attributes(status: 'done', delivered_count: 0)
      expect(mock).not_to have_received(:quote_proposal)
    end
  end

  # A LINHA EM VOO NO DEPLOY: o handle é o que a versão anterior grava depois da segunda consulta —
  # preço publicado e aceito, a identidade dele, a lista de acionadas —, sem a chave de tentativas do
  # comparativo. A primeira passada desta versão encerra com o PDF e um desfecho só.
  it 'a linha que atravessou o deploy conclui com o comparativo e um desfecho so' do
    # Arrange
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    texto = "Primeiros preços:\n\n• *Seguradora 8*: R$ 2.119,18 no total"
    publicado = Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(texto)
    Autonomia::Agents::Tools::EntregaAceita.registrar(run, texto, publicado)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1', 'produto' => 'auto',
                                  cotacao::DELIVERED_KEY => %w[8], cotacao::ACIONADAS_KEY => %w[11 19 20 47 8],
                                  cotacao::PRECO_LEGADO_KEY => false,
                                  cotacao::PRECOS_KEY => [Autonomia::Agents::Tools::EntregaPublicada.token_de(run, texto)] })
    pdf_responde(pdf_ok)
    portal_responde('partial', [oferta('8', 'quoted', 2119.18), oferta('20', 'declined'), oferta('47', 'declined'),
                                oferta('11', 'auth_required'), oferta('19', 'declined')])

    # Act
    passada(run, 7)

    # Assert
    expect(bot_contents).to eq([texto, cotacao::Comparativo::LEGENDA, fecho])
    expect(run.status).to eq('done')
  end

  # O VARREDOR, NO MEIO DE UMA NOVA TENTATIVA: a corrente de jobs morreu depois de a passada gravar o
  # portal fechado e a primeira tentativa do comparativo. Ele não pede o PDF (não começa trabalho
  # novo) e diz o fecho de quem tem resultado — sobrou o comparativo.
  it 'o varredor fecha com o fecho de quem tem resultado a linha abandonada esperando nova tentativa' do
    # Arrange
    run = cotacao_submetida
    ate_a_leitura_parcial(run)
    portal_responde('partial', leitura_com_todas_com_desfecho)
    allow(mock).to receive(:quote_proposal).and_raise(portal_fora)
    passada(run, 3)
    run.update!(expires_at: 10.minutes.ago)

    # Act
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq([precos, fecho])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
    expect(mock).to have_received(:quote_proposal).once
  end

  # A REGRA DO MOTOR, COM UMA FERRAMENTA QUALQUER: só a entrega de ARQUIVO recusada segura o `done`.
  # A de texto recusada (a pergunta pelo dado que falta é devolvida em toda passada) encerra como antes.
  describe 'o motor, com uma ferramenta qualquer' do
    def execucao_generica
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'id' => 'cot-1' })
      run
    end

    it 'a passada done cuja entrega de arquivo o publicador recusou e reagendada, e nao encerra' do
      # Arrange
      forma = Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: 'arquivo.pdf', legenda: 'segue o arquivo',
                                                             reserva: 'segue').to_h
      register_async_tool(build_async_tool(poll: Autonomia::Agents::Tools::Progress.done(deliveries: [forma])))
      pdf_responde(pdf_nao_encontrado)
      run = execucao_generica

      # Act
      passada(run, 1)

      # Assert
      expect(run.status).to eq('running')
      expect(described_class).to have_been_enqueued.with(run.id, 2)
      expect(bot_contents).to be_empty
    end

    # A PUBLICAÇÃO DO DESFECHO QUE LEVANTA não fecha a linha: a passada é tratada como falha e tentada
    # de novo, como acontecia antes desta fatia quando a publicação do `finish_done` levantava (o
    # enfileiramento da publicação adiada, com o Redis fora). A passada seguinte publica um fecho só.
    it 'o desfecho cuja publicacao levanta nao fecha a linha, e a passada seguinte o publica uma vez' do
      # Arrange
      register_async_tool(build_async_tool(poll: Autonomia::Agents::Tools::Progress.done(deliveries: ['um preco']),
                                           resultado: true))
      run = execucao_generica
      primeiro = described_class.new
      allow(primeiro).to receive(:publish).and_wrap_original do |original, execucao, entrega|
        raise Redis::CannotConnectError, 'redis fora' if entrega == 'encerrei a consulta por aqui'

        original.call(execucao, entrega)
      end

      # Act 1
      primeiro.perform(run.id, 1)

      # Assert 1 — o preço saiu, o fecho não, e a linha segue viva e reagendada
      expect(bot_contents).to eq(['um preco'])
      expect(run.reload.status).to eq('running')
      expect(described_class).to have_been_enqueued.with(run.id, 2)

      # Act 2
      passada(run, 2)

      # Assert 2
      expect(bot_contents).to eq(['um preco', 'encerrei a consulta por aqui'])
      expect(run.status).to eq('done')
    end

    it 'a passada done cuja entrega de texto o publicador recusou encerra como antes' do
      # Arrange
      register_async_tool(build_async_tool(poll: Autonomia::Agents::Tools::Progress.done(deliveries: ['me diga a placa'])))
      original = Messages::MessageBuilder.method(:new)
      allow(Messages::MessageBuilder).to receive(:new) do |*args|
        raise ActiveRecord::StatementInvalid, 'canal fora' if args[2][:content].to_s.include?('placa')

        original.call(*args)
      end
      run = execucao_generica

      # Act
      passada(run, 1)

      # Assert
      expect(run.status).to eq('done')
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end
  end
end
