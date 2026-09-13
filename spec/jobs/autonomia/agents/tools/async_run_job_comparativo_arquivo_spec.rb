require 'rails_helper'

# O COMPARATIVO CHEGA COMO ARQUIVO, PELO CAMINHO REAL (entrega 11, termos 1, 2, 3 e 5).
#
# O job roda sobre uma execução da ferramenta de cotação DE VERDADE, com o conector `mock`, no
# estado em que o comparativo sai no fim (submetida, preço já entregue, prazo vencido), e o que se
# lê na conversa é o que o cliente leria: o PDF como ANEXO, com o nome que diz o que ele é — e os
# preços que já saíram continuam lá.
#
# O LINK DO PORTAL NÃO SAI MAIS (fatia 1 do PDF rápido, 13/09/2026): a URL não tem assinatura, leva o
# nome do segurado no caminho e baixa sem autenticação. Até essa data, o download que falhava mandava
# o texto com o link; agora é um comparativo que não saiu, e os exemplos de falha abaixo afirmam a
# ausência do link e o que acontece no lugar dele.
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
  # A URL que o conector `mock` devolve para o comparativo desta cotação.
  let(:url) { 'https://exemplo.test/comparativo-mock.pdf' }
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }
  let(:preco) { '*Porto Seguro* R$ 1.200,50 por ano.' }

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
    # O `SafeFetch` resolve o nome antes de conectar (é assim que ele confere o endereço): o host de
    # teste ganha um endereço público, e o WebMock responde a chamada.
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
  end

  def bot_messages
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  end

  # A execução com um preço JÁ PUBLICADO na conversa (pelo publicador de verdade) e o prazo vencido:
  # o comparativo é o que ainda vale entregar.
  def cotacao_com_preco_publicado_e_prazo_vencido
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    token = publicar_e_aceitar!(run, preco)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'mock-1:1',
                                  cotacao::DELIVERED_KEY => ['8'], 'produto' => 'auto',
                                  cotacao::PRECO_LEGADO_KEY => false, cotacao::PRECOS_KEY => [token] })
    run
  end

  # PUBLICA PELO CAMINHO REAL E PASSA PELO ACEITE, como o motor faz (`AsyncRunJob#deliver`), e
  # devolve o TOKEN da entrega. Levanta se a publicação não entrar: um Arrange que mente sobre o que
  # o cliente recebeu não prova nada.
  #
  # O ACEITE É O PONTO (rodada 5): o encerramento só pede o comparativo a quem TEM preço na tela, e
  # a pergunta é ao aceite — a identidade emitida (`PRECOS_KEY`) cruzada com a lista que o publicador
  # escreve ao assumir a entrega. Publicar direto, sem registrar o aceite e sem a cobertura
  # `preco_legado`, fazia os dois exemplos do comparativo passarem pela PROVA LEGADA (`entregues`
  # não vazio) em vez do cruzamento que dizem exercitar.
  def publicar_e_aceitar!(run, entrega)
    publicador = Autonomia::Agents::Tools::AsyncPublisher.new(run: run)
    resultado = Autonomia::Agents::Tools::EntregaAceita.registrar(run, entrega, publicador.publish(entrega))
    raise "o Arrange nao publicou a entrega: #{resultado.status}" unless resultado.published?

    run.record_delivery!
    Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
  end

  it 'entrega o comparativo como anexo, nomeado pela placa, e depois o fecho' do
    # Arrange
    run = cotacao_com_preco_publicado_e_prazo_vencido
    stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — o preço, o arquivo (legenda sem link), o fecho
    expect(bot_messages.map(&:content)).to eq([preco, cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    anexo = bot_messages.second.attachments.sole
    expect(anexo.file_type).to eq('file')
    expect(anexo.file.filename.to_s).to eq('Comparativo de seguro, placa ABC1D23.pdf')
    expect(anexo.file).to have_attributes(content_type: 'application/pdf', download: pdf)
    expect(bot_messages.map(&:content).join).not_to include(url)
    expect(run.reload.status).to eq('failed')
    # O blob anexado nunca vai para a limpeza (rodada 5): o `download` acima ainda funcionaria com
    # o `PurgeJob` só enfileirado, então a afirmação é sobre a fila.
    expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
  end

  # O 404 do armazenamento do portal (XML de `BlobNotFound`), pela porta do prazo. O link não sai, o
  # preço que já saiu fica, a entrega não conta, e o fecho de quem tem resultado sai do mesmo jeito.
  it 'nao manda o link quando o download falha, sem apagar o preco que ja saiu' do
    # Arrange
    run = cotacao_com_preco_publicado_e_prazo_vencido
    stub_request(:get, url).to_return(status: 404, body: '<Error><Code>BlobNotFound</Code></Error>',
                                      headers: { 'Content-Type' => 'application/xml' })
    entregues_antes = run.delivered_count

    # Act
    described_class.new.perform(run.id, 5)

    # Assert
    expect(bot_messages.map(&:content)).to eq([preco, cotacao::FECHO_COM_RESULTADO])
    expect(bot_messages.map(&:content).join).not_to include(url)
    expect(bot_messages.flat_map(&:attachments)).to be_empty
    expect(run.reload.delivered_count).to eq(entregues_antes)
    expect(run.status).to eq('failed')
  end

  # O CAMINHO DA CONSULTA (`apply`), com a URL que a forma recusa. Até 13/09/2026 o cliente recebia o
  # link em texto; agora a forma recusada é um comparativo que não saiu: nada novo na conversa, nenhuma
  # sentinela de comparativo enviado, e a execução segue para a nova tentativa.
  it 'nao manda o link pela consulta quando a URL do portal nao tem a forma segura, e tenta de novo' do
    # Arrange — cotação completa no mock (`mock-0:1`), todos os preços já entregues (as quatro
    # ofertas do `mock_progress` completo: 8, 3, 55 mensal e 999 sem período), prazo vivo
    url_http = 'http://exemplo.test/comparativo-mock.pdf'
    mock = Autonomia::Insurance::Connector::Mock.new
    allow(mock).to receive(:quote_proposal).and_return('quote_id' => 'mock-0:1', 'url' => url_http)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(mock)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'mock-0:1',
                                  cotacao::DELIVERED_KEY => %w[8 3 55 999], 'produto' => 'auto' })
    Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(preco)
    run.record_delivery!

    # Act
    described_class.new.perform(run.id, 1)

    # Assert — o preço fica, o link não sai, nada é marcado como enviado, e a execução continua
    expect(bot_messages.map(&:content)).to eq([preco])
    expect(bot_messages.flat_map(&:attachments)).to be_empty
    expect(run.reload.handle[cotacao::PDF_SENT_KEY]).to be_blank
    expect(run.delivered_count).to eq(1)
    expect(run.status).to eq('running')
    expect(described_class).to have_been_enqueued.with(run.id, 2)
  end

  it 'nao manda o link tambem quando a URL responde algo que nao e PDF' do
    run = cotacao_com_preco_publicado_e_prazo_vencido
    stub_request(:get, url).to_return(status: 200, body: '<html>manutenção</html>', headers: { 'Content-Type' => 'text/html' })

    described_class.new.perform(run.id, 5)

    expect(bot_messages.map(&:content)).to eq([preco, cotacao::FECHO_COM_RESULTADO])
    expect(bot_messages.flat_map(&:attachments)).to be_empty
  end

  # A FALHA DO ANEXO DEPOIS DE UM DOWNLOAD BOM, pelo caminho da consulta (rodada 3, P2). O arquivo é
  # gravado antes da mensagem, e a falha do armazenamento é tratada como a do download. Até 13/09/2026
  # isso mandava o link em texto; agora nenhuma mensagem nasce, a entrega não conta, a linha do blob
  # sem arquivo vai para a limpeza, e a execução continua para a nova tentativa do comparativo.
  it 'nao manda o link pela consulta quando o armazenamento falha depois do download' do
    # Arrange — cotação completa no mock (`mock-0:1`), todos os preços já entregues, prazo vivo
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'mock-0:1',
                                  cotacao::DELIVERED_KEY => %w[8 3 55 999], 'produto' => 'auto' })
    Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(preco)
    run.record_delivery!
    stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
    allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)

    # Act
    described_class.new.perform(run.id, 1)

    # Assert — o preço fica, nenhum link, nada de anexo, a entrega não conta; a linha do blob sem
    # arquivo (a subida falhou depois de a linha ser salva, rodada 6) vai para a limpeza em segundo
    # plano; o comparativo foi emitido e não foi aceito, e a execução é reagendada
    expect(bot_messages.map(&:content)).to eq([preco])
    expect(bot_messages.flat_map(&:attachments)).to be_empty
    expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(run.reload.handle[cotacao::PDF_SENT_KEY]).to be(true)
    expect(run).to have_attributes(delivered_count: 1, status: 'running')
  end
end
