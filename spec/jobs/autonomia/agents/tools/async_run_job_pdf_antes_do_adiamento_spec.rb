require 'rails_helper'

# O PDF É BAIXADO ANTES DE A PUBLICAÇÃO SER ADIADA (fatia 1 do PDF rápido, rodada 2, 13/09/2026).
#
# A revisão adversarial da PR #422 reprovou a primeira rodada por uma causa só: o download do comparativo
# acontecia no publicador DEPOIS da passada, e com a cadeia humanizada do turno aberta (o cliente escreveu
# no meio, um humano assumiu) a publicação era adiada sem baixar nada. O motor lia `deferred` como aceito,
# fechava `done` e publicava o fecho; no `AsyncPublishJob` o download falhava e ninguém pedia outro PDF.
#
# Cada exemplo aqui é uma sonda do revisor virada do avesso: a sonda afirmava o defeito observado, este
# arquivo afirma o que o cliente deve ver. Dados sintéticos, conector `mock`, publicador real e download
# pelo WebMock.
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
  let(:url) { 'https://exemplo.test/comparativo-mock.pdf' }
  let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }
  let(:fecho) { cotacao::FECHO_COM_RESULTADO }

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
  end

  def oferta(code, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    return base unless amount

    base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' })
  end

  def leitura_inicial = %w[8 20 47].map { |codigo| oferta(codigo, 'running') }
  def com_desfecho = [oferta('8', 'quoted', 2119.18), oferta('20', 'quoted', 2323.17), oferta('47', 'declined')]

  def portal_responde(status, ofertas)
    allow(mock).to receive(:quote_result).and_return({ 'quote_id' => 'q-1:1', 'status' => status, 'offers' => ofertas })
  end

  def pdf_ok = { status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' } }

  def pdf_nao_encontrado
    { status: 404, body: '<Error><Code>BlobNotFound</Code></Error>', headers: { 'Content-Type' => 'application/xml' } }
  end

  # A cadeia humanizada do turno ABERTA: dois pedaços esperados e nenhum postado — é o turno cujo
  # `ChunkedDeliveryJob` foi abortado porque o cliente escreveu no meio.
  def cotacao_submetida(cadeia_aberta: false, expires_at: 5.minutes.from_now)
    origem = cadeia_aberta ? create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming) : nil
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                                    origin_message_id: origem&.id })
    run.promote!(expected_chunks: cadeia_aberta ? 2 : 0, notify_customer: false, expires_at: expires_at)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1',
                                  cotacao::DELIVERED_KEY => [], 'produto' => 'auto' })
    run
  end

  def passada(run, tentativa)
    described_class.new.perform(run.id, tentativa)
    run.reload
  end

  # Até a cotação fechar sem esperar o portal: a lista inicial, e depois duas leituras seguidas com o
  # mesmo conjunto de seguradoras, todas com desfecho. -> o número da próxima passada.
  def ate_fechar(run, primeira: 1)
    portal_responde('running', leitura_inicial)
    passada(run, primeira)
    portal_responde('partial', com_desfecho)
    passada(run, primeira + 1)
    passada(run, primeira + 2)
    primeira + 3
  end

  def bot_messages = conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  def conteudos = bot_messages.map(&:content)
  def anexos = bot_messages.flat_map(&:attachments)

  def adiados
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == 'Autonomia::Agents::Tools::AsyncPublishJob' }
  end

  # Os `AsyncPublishJob` enfileirados, até a fila deles esvaziar — a cadeia do turno nunca fecha, então cada
  # um roda com o teto de adiamentos da cadeia. `inversa: true` roda cada lote do último enfileirado para o
  # primeiro: é o Sidekiq pegando o job do fecho antes do job do PDF.
  def drenar_publicacoes_adiadas(inversa: false)
    8.times do
      jobs = adiados
      break if jobs.empty?

      ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| jobs.include?(job) }
      (inversa ? jobs.reverse : jobs).each do |job|
        argumentos = ActiveJob::Arguments.deserialize(job['arguments'])
        Autonomia::Agents::Tools::AsyncPublishJob.new.perform(argumentos[0], argumentos[1],
                                                              [argumentos[2].to_i, Autonomia::Agents::Tools::AsyncConfig::MAX_PUBLISH_DEFERRALS].max)
      end
    end
  end

  # O último pedaço da cadeia do turno sai (`cotacao_submetida(cadeia_aberta: true)` espera dois).
  def fechar_cadeia(run)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent_bot,
                     content: 'pedaço final do turno', content_attributes: { 'autonomia_chunk_token' => "#{run.origin_message_id}:1" })
  end

  # O que o cliente vê, na ordem, sem os pedaços do turno.
  def ordem
    bot_messages.reject { |mensagem| mensagem.content_attributes.to_h['autonomia_chunk_token'] }.map do |mensagem|
      next 'pdf' if mensagem.attachments.any?
      next 'fecho' if mensagem.content == fecho

      mensagem.content.to_s.include?('R$') ? 'precos' : 'outro'
    end
  end

  def tipo_do_job(job)
    forma = ActiveJob::Arguments.deserialize(job['arguments'])[1]
    return 'pdf' if Autonomia::Agents::Tools::ArquivoGravado.de(forma)
    return 'fecho' if Autonomia::Agents::Tools::EntregaEncadeada.de(forma) || forma == fecho

    forma.to_s.include?('R$') ? 'precos' : 'outro'
  end

  # A DRENAGEM PASSO A PASSO (rodada 3): a cada tique, cada `AsyncPublishJob` enfileirado roda UMA vez, com
  # o PRÓPRIO contador de adiamentos, sem saltar para o teto. `segurar` (tipo => tiques) deixa os jobs de um
  # tipo parados nos primeiros tiques, como o poller que chega atrasado para eles; `primeiro` roda os jobs
  # de um tipo antes dos outros dentro de cada tique.
  def drenar_passo_a_passo(segurar: {}, primeiro: nil, tiques: 90)
    tiques.times do |tique|
      break if adiados.empty?

      rodar_tique(adiados.reject { |job| segurar.fetch(tipo_do_job(job), 0) > tique }, primeiro)
    end
  end

  def rodar_tique(jobs, primeiro)
    ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| jobs.any? { |rodando| rodando.equal?(job) } }
    jobs.sort_by.with_index { |job, indice| [tipo_do_job(job) == primeiro ? 0 : 1, indice] }.each do |job|
      Autonomia::Agents::Tools::AsyncPublishJob.new.perform(*ActiveJob::Arguments.deserialize(job['arguments']))
    end
  end

  describe 'sonda A: comparativo com a cadeia aberta e o download falhando' do
    it 'a passada nao encerra, o fecho nao sai, e a passada seguinte pede outro PDF' do
      # Arrange
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_nao_encontrado, pdf_ok)

      # Act 1 — até a passada que fecha a cotação: o download falha nela, antes de adiar
      proxima = ate_fechar(run)

      # Assert 1
      expect(run.status).to eq('running')
      expect(adiados.map { |job| ActiveJob::Arguments.deserialize(job['arguments'])[1] }.to_s).not_to include(url)

      # Act 2 — a passada seguinte pede outro comparativo, e desta vez ele baixa
      passada(run, proxima)
      drenar_publicacoes_adiadas

      # Assert 2 — o PDF, e nenhum fecho depois dele
      expect(mock).to have_received(:quote_proposal).twice
      expect(anexos.size).to eq(1)
      expect(conteudos).not_to include(fecho)
      expect(conteudos.join).not_to include(url)
      expect(run.status).to eq('done')
    end

    # A LIA NÃO FICA TRAVADA POR 24 h por uma cotação cujo download do PDF foi recusado: enquanto a nova
    # tentativa não acontece, a linha não está concluída e o contador não conta nada. O PDF ACEITO e
    # ADIADO é outro caso: a linha já é `done`, e o especialista lê "concluída" antes de o PDF sair (sonda U2
    # da revisão da rodada 2; declarado na auditoria).
    it 'o pedido repetido nao diz concluida enquanto o PDF recusado espera a nova tentativa' do
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_nao_encontrado)

      ate_fechar(run)
      drenar_publicacoes_adiadas

      expect(run.reload.status).to eq('running')
      expect(Autonomia::Agents::Tools::PedidoRepetido.new(run).to_s).not_to include('concluída')
      expect(run.delivered_count).to eq(0)
    end
  end

  describe 'sonda B: o prazo vence depois de um download recusado, com tentativa sobrando' do
    it 'o encerramento por prazo pede o PDF de novo, e ele e a ultima palavra' do
      # Arrange — as passadas seguem até a primeira tentativa do comparativo, cujo download falha
      run = cotacao_submetida
      stub_request(:get, url).to_return(pdf_nao_encontrado, pdf_ok)
      portal_responde('running', leitura_inicial)
      passada(run, 1)
      portal_responde('partial', com_desfecho)
      tentativa = 2
      tentativa += 1 while passada(run, tentativa).running? && run.handle['comparativo_tentativas'].to_i.zero? && tentativa < 6
      expect(run).to have_attributes(status: 'running')
      expect(run.handle['comparativo_tentativas']).to eq(1)

      # Act — o prazo vence antes da passada seguinte
      run.update!(expires_at: 1.second.ago)
      passada(run, tentativa + 1)

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(mock).to have_received(:quote_proposal).twice
      expect(anexos.size).to eq(1)
      expect(conteudos.last).to eq(cotacao::Comparativo::LEGENDA)
      expect(conteudos).not_to include(fecho)
    end

    # CADA PEDIDO AO PORTAL DEVOLVE OUTRA URL: a identidade gravada no handle é a da tentativa que falhou, e
    # o fecho só se encadeia ao PDF do encerramento pela entrega que o próprio encerramento adiou.
    it 'com a cadeia aberta, o PDF do encerramento sai adiado, e nenhum fecho depois dele' do
      # Arrange
      run = cotacao_submetida(cadeia_aberta: true)
      outra_url = 'https://exemplo.test/comparativo-mock-2.pdf'
      allow(mock).to receive(:quote_proposal).and_return({ 'url' => url }, { 'url' => outra_url })
      stub_request(:get, url).to_return(pdf_nao_encontrado)
      stub_request(:get, outra_url).to_return(pdf_ok)
      proxima = ate_fechar(run)
      expect(run).to have_attributes(status: 'running')
      expect(run.handle['comparativo_tentativas']).to eq(1)

      # Act — o prazo vence; o encerramento pede o PDF, que baixa e é adiado; o job do fecho é pego primeiro
      run.update!(expires_at: 1.second.ago)
      passada(run, proxima)
      drenar_publicacoes_adiadas(inversa: true)

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(anexos.size).to eq(1)
      expect(conteudos).not_to include(fecho)
    end
  end

  describe 'sonda C: a lista de ofertas que cresce entre leituras' do
    it 'a seguradora listada depois entra no preco e a cotacao so fecha com a lista estavel' do
      # Arrange
      run = cotacao_submetida
      stub_request(:get, url).to_return(pdf_ok)

      # Act — duas seguradoras, depois as mesmas duas com desfecho, depois a terceira aparece e cota
      portal_responde('partial', [oferta('8', 'running'), oferta('20', 'running')])
      passada(run, 1)
      portal_responde('partial', [oferta('8', 'quoted', 2119.18), oferta('20', 'declined')])
      passada(run, 2)
      expect(run.status).to eq('running')
      portal_responde('partial', [oferta('8', 'quoted', 2119.18), oferta('20', 'declined'), oferta('47', 'quoted', 1500.0)])
      passada(run, 3)
      expect(run.status).to eq('running')
      passada(run, 4)

      # Assert
      expect(run.handle[cotacao::DELIVERED_KEY]).to include('47')
      expect(run.status).to eq('done')
      expect(run.handle[cotacao::ACIONADAS_KEY]).to eq(%w[20 47 8])
    end
  end

  describe 'sonda E: o preço recusado pelo publicador e o PDF aceito na passada que fecha' do
    it 'o PDF chegou ao cliente, e ele e a ultima palavra' do
      # Arrange — a publicação do lote de preços cai
      run = cotacao_submetida
      stub_request(:get, url).to_return(pdf_ok)
      portal_responde('running', leitura_inicial)
      passada(run, 1)
      original = Messages::MessageBuilder.method(:new)
      allow(Messages::MessageBuilder).to receive(:new) do |*args|
        raise ActiveRecord::StatementInvalid, 'canal fora' if args[2][:content].to_s.include?('2.119,18')

        original.call(*args)
      end
      portal_responde('partial', com_desfecho)
      passada(run, 2)
      allow(Messages::MessageBuilder).to receive(:new).and_call_original

      # Act
      passada(run, 3)
      passada(run, 4) if run.running?

      # Assert
      expect(run.status).to eq('done')
      expect(conteudos).to eq([cotacao::Comparativo::LEGENDA])
    end
  end

  describe 'sonda V: quem terminou com o comparativo nao recebe fecho, nem antes nem depois do PDF' do
    it 'com a passada morta antes do finish! e o varredor antes dos adiados: o PDF, e nenhum fecho' do
      # Arrange — toda passada do motor morre antes do `finish!`, seja qual for a que fecha a cotação
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_ok)
      allow(Autonomia::Agents::ToolRun).to receive(:find_by).and_call_original
      allow(Autonomia::Agents::ToolRun).to receive(:find_by).with(id: run.id).and_return(run)
      allow(run).to receive(:finish!).and_return(false)
      ate_fechar(run)
      RSpec::Mocks.space.proxy_for(run).reset
      RSpec::Mocks.space.proxy_for(Autonomia::Agents::ToolRun).reset
      Autonomia::Agents::ToolRun.where(id: run.id).update_all(expires_at: 10.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      # Act
      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform
      antes_dos_adiados = conteudos
      drenar_publicacoes_adiadas

      # Assert
      expect(antes_dos_adiados).not_to include(fecho)
      expect(conteudos).not_to include(fecho)
      expect(anexos.size).to eq(1)
    end

    it 'pelo motor, com a cadeia aberta e os jobs adiados pegos na ordem inversa: so o PDF, nenhum fecho' do
      # Arrange
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_ok)
      ate_fechar(run)
      argumentos = adiados.map { |job| ActiveJob::Arguments.deserialize(job['arguments'])[1] }
      expect(argumentos).to include(a_hash_including(Autonomia::Agents::Tools::ArquivoGravado::CHAVE))
      expect(argumentos.to_s).not_to include(url)

      # Act
      drenar_publicacoes_adiadas(inversa: true)

      # Assert
      expect(conteudos).not_to include(fecho)
    end
  end

  # O FECHO SAI DEPOIS DE TODA ENTREGA ACEITA QUE AINDA NÃO É MENSAGEM (rodada 3 da fatia 1 do PDF rápido). Os
  # exemplos do lote de preços adiado saíram com o lote (fatia 3 do #420); fica o PDF que o encerramento adiou.
  describe 'o fecho depois de toda entrega aceita que ainda nao e mensagem' do
    # A ENTREGA QUE O PRÓPRIO ENCERRAMENTO ADIOU segura o fecho mesmo quando a escrita do aceite falha: o
    # token dela não chega à lista do aceite, e o encerramento o guarda (`@adiada`).
    it 'o fecho do prazo espera o PDF que o encerramento adiou, com a escrita do aceite falhando' do
      # Arrange — a primeira tentativa do PDF falha no download
      run = cotacao_submetida(cadeia_aberta: true)
      outra_url = 'https://exemplo.test/comparativo-mock-2.pdf'
      allow(mock).to receive(:quote_proposal).and_return({ 'url' => url }, { 'url' => outra_url })
      stub_request(:get, url).to_return(pdf_nao_encontrado)
      stub_request(:get, outra_url).to_return(pdf_ok)
      proxima = ate_fechar(run)
      drenar_passo_a_passo
      expect(ordem).to eq([])
      allow(Autonomia::Agents::ToolRun).to receive(:find_by).and_call_original
      allow(Autonomia::Agents::ToolRun).to receive(:find_by).with(id: run.id).and_return(run)
      allow(run).to receive(:registrar_entrega_aceita!).and_raise(ActiveRecord::StatementInvalid, 'banco fora')
      run.update!(expires_at: 1.second.ago)

      # Act — o encerramento pede o PDF, que é adiado; o job do fecho é pego antes em cada tique
      passada(run, proxima)
      RSpec::Mocks.space.proxy_for(run).reset
      RSpec::Mocks.space.proxy_for(Autonomia::Agents::ToolRun).reset
      drenar_passo_a_passo(primeiro: 'fecho')

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(ordem).to eq(%w[pdf fecho])
    end

    # O CASO EM QUE O FECHO AINDA EXISTE, E É POR ELE QUE A ORDEM IMPORTA (21/09/2026). Desde que quem
    # termina com o comparativo não recebe fecho, o fecho de quem tem resultado só sai quando sobrou algo de
    # verdade: o prazo venceu com seguradora ainda sem resposta. É o caso natural de produção, sem falha de
    # banco nenhuma, e ele precisa da mesma garantia: o fecho nunca chega antes do PDF que ele encerra.
    it 'o prazo com seguradora ainda sem resposta: o PDF sai, e o fecho vem depois dele' do
      # Arrange — duas cotaram, a terceira nunca responde
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_ok)
      portal_responde('running', leitura_inicial)
      passada(run, 1)
      portal_responde('partial', [oferta('8', 'quoted', 2119.18), oferta('20', 'quoted', 2323.17), oferta('47', 'running')])
      passada(run, 2)

      # Act — o prazo vence; o job do fecho é pego antes do job do PDF em cada tique
      run.update!(expires_at: 1.second.ago)
      passada(run, 3)
      drenar_passo_a_passo(primeiro: 'fecho')

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(ordem.count('fecho')).to eq(1)
      expect(ordem.index('fecho')).to be > ordem.index('pdf')
    end
  end

  # A REENTRADA DEPOIS DE UMA PASSADA QUE NÃO GRAVOU O HANDLE (a revisão da rodada 2 apontou: na `main` o
  # comparativo da cotação com recusa era gerado sob a marca `autonomia_closed`, e o `fechar` gera sem ela). A
  # mesma passada roda de novo sobre o handle do banco quando o `perform` levanta para o Sidekiq (o
  # `record_attempt!` de `retry_or_fail` falhando no banco, com `:max_retries: 3`). No deploy de produção, não:
  # o `docker stop` sem `-t` mata o worker em 10 s, sem reenfileirar, e quem fecha a linha é o varredor. A
  # passada abaixo publica o PDF e levanta antes de gravar o handle (`Interrupt`, que o `advance` não captura).
  # Cada pedido ao portal devolve outra URL: um segundo pedido seria um segundo PDF na conversa.
  describe 'a reentrada depois de a passada que publicou o PDF morrer antes de gravar o handle' do
    { 'imediata' => false, 'adiada' => true }.each do |publicacao, cadeia_aberta|
      it "com a publicacao #{publicacao} do PDF, a reentrada nao pede um segundo comparativo" do
        # Arrange
        run = cotacao_submetida(cadeia_aberta: cadeia_aberta)
        outra_url = 'https://exemplo.test/comparativo-mock-2.pdf'
        allow(mock).to receive(:quote_proposal).and_return({ 'url' => url }, { 'url' => outra_url })
        stub_request(:get, url).to_return(pdf_ok)
        stub_request(:get, outra_url).to_return(pdf_ok)
        portal_responde('running', leitura_inicial)
        passada(run, 1)
        portal_responde('partial', com_desfecho)
        passada(run, 2)
        allow(Autonomia::Agents::ToolRun).to receive(:find_by).and_call_original
        allow(Autonomia::Agents::ToolRun).to receive(:find_by).with(id: run.id).and_return(run)
        allow(run).to receive(:record_attempt!).and_raise(Interrupt)
        expect { described_class.new.perform(run.id, 3) }.to raise_error(Interrupt)
        RSpec::Mocks.space.proxy_for(run).reset
        RSpec::Mocks.space.proxy_for(Autonomia::Agents::ToolRun).reset

        # Act — o job reenfileirado roda a mesma passada
        passada(run, 3)
        drenar_publicacoes_adiadas

        # Assert
        expect(mock).to have_received(:quote_proposal).once
        expect(anexos.size).to eq(1)
        expect(conteudos).not_to include(fecho)
        expect(run.reload.status).to eq('done')
      end
    end
  end

  # O PRAZO NO MEIO DAS NOVAS TENTATIVAS. O prazo só é conferido no começo de uma passada (`AsyncRunJob#stop?`).
  describe 'o prazo que vence no meio das tentativas do comparativo' do
    it 'vencido durante a passada cujo download falha: a passada termina, e o encerramento pede o PDF de novo' do
      # Arrange — o download falha, e o relógio passa do prazo enquanto ele acontece
      run = cotacao_submetida(expires_at: 2.minutes.from_now)
      stub_request(:get, url).to_return(lambda { |_request|
        travel(5.minutes)
        pdf_nao_encontrado
      }, pdf_ok)
      ate_fechar(run)
      expect(run).to have_attributes(status: 'running')
      expect(run.expires_at).to be < Time.current

      # Act — a passada seguinte encontra o prazo vencido
      passada(run, 4)

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(mock).to have_received(:quote_proposal).twice
      expect(anexos.size).to eq(1)
      expect(conteudos).not_to include(fecho)
    end

    it 'vencido com o teto de tentativas esgotado: o encerramento nao pede mais, e diz que os valores podem ser pedidos' do
      # Arrange — três passadas de comparativo com o download falhando; a terceira volta recusada e reagenda
      run = cotacao_submetida
      stub_request(:get, url).to_return(pdf_nao_encontrado)
      proxima = ate_fechar(run)
      passada(run, proxima)
      passada(run, proxima + 1)
      expect(run).to have_attributes(status: 'running')
      expect(run.handle[cotacao::Comparativo::TENTATIVAS_KEY]).to eq(cotacao::Comparativo::TETO_DE_TENTATIVAS)

      # Act — o prazo vence antes da passada seguinte
      run.update!(expires_at: 1.second.ago)
      passada(run, proxima + 2)

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(mock).to have_received(:quote_proposal).exactly(3).times
      expect(anexos).to be_empty
      expect(conteudos).to eq([cotacao.valores_message(run.arguments)])
    end

    it 'sem prazo vencido, o teto esgotado encerra done sem o PDF, dizendo que os valores podem ser pedidos' do
      # Arrange
      run = cotacao_submetida
      stub_request(:get, url).to_return(pdf_nao_encontrado)
      proxima = ate_fechar(run)
      passada(run, proxima)
      passada(run, proxima + 1)

      # Act — a passada seguinte não tem o que tentar
      passada(run, proxima + 2)

      # Assert
      expect(run.status).to eq('done')
      expect(mock).to have_received(:quote_proposal).exactly(3).times
      expect(anexos).to be_empty
      expect(conteudos).to eq([cotacao.valores_message(run.arguments)])
    end

    # O ENCERRAMENTO INSISTE (chat#585): sem passada seguinte, a falha do portal ganha outra chance na mesma passada,
    # com espera (`ESPERAS_DO_COMPARATIVO`). Portal fora nas três: diz que os valores podem ser pedidos.
    it 'vencido com tentativa sobrando e o portal fora: o encerramento insiste, e diz que os valores podem ser pedidos' do
      # Arrange
      run = cotacao_submetida
      allow_any_instance_of(cotacao).to receive(:esperar_o_portal) # rubocop:disable RSpec/AnyInstance
      allow(mock).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, '504'))
      proxima = ate_fechar(run)
      expect(run.status).to eq('running')

      # Act
      run.update!(expires_at: 1.second.ago)
      passada(run, proxima)

      # Assert
      expect(run).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(mock).to have_received(:quote_proposal).exactly(1 + 1 + cotacao::ESPERAS_DO_COMPARATIVO.size).times
      expect(anexos).to be_empty
      expect(conteudos).to eq([cotacao.valores_message(run.arguments)])
    end
  end

  # O BLOB DE UMA TENTATIVA ABANDONADA NÃO FICA NO ARMAZENAMENTO: gravado antes de adiar, ele leva a marca
  # da execução (`EntregaDeArquivo.marca`), e o varredor apaga o marcado, sem anexo e com mais de uma hora.
  describe 'o blob gravado antes de adiar' do
    it 'a publicacao adiada que nunca roda deixa um blob que o varredor apaga depois de uma hora' do
      # Arrange — a passada que fecha grava o blob e adia; o job adiado some (Redis perdido)
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_ok)
      ate_fechar(run)
      blob = ActiveStorage::Blob.where("metadata LIKE '%autonomia_tool_run_id%'").sole
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      # Act
      travel(2.hours) { Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform }
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)

      # Assert
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    end

    it 'a publicacao adiada de uma execucao que morreu nao anexa e manda o blob para a limpeza' do
      # Arrange — o blob foi gravado na passada que fechou, antes de adiar
      run = cotacao_submetida(cadeia_aberta: true)
      stub_request(:get, url).to_return(pdf_ok)
      ate_fechar(run)
      expect(ActiveStorage::Blob.count).to eq(1)
      Autonomia::Agents::ToolRun.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations

      # Act
      drenar_publicacoes_adiadas
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)

      # Assert
      expect(anexos).to be_empty
      expect(ActiveStorage::Blob.count).to eq(0)
    end
  end
end
