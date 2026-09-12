require 'rails_helper'

# A FRASE DE ENCERRAMENTO PARCIAL DA COTAÇÃO, PELO CAMINHO REAL (entrega 4).
#
# Quando o prazo estoura e ALGUMAS seguradoras já responderam, o cliente precisa ler "algumas
# SEGURADORAS não responderam a tempo" — e não o texto genérico do `Base`, "algumas consultas". A
# frase de seguros nasceu em 08/09/2026 (`c7ae6997e1`) e nunca rodou: era método de instância, e o
# `AsyncRunJob` publica o fecho pela CLASSE. Rodrigo recebeu a frase genérica em 09/09.
#
# Este exemplo NÃO chama `partial_message` direto (um teste assim passava com o defeito no lugar):
# ele roda o job sobre uma execução da ferramenta de cotação real, no ESTADO PREPARADO em que o
# defeito aparecia — submetida, com um preço contado como entregue, prazo vencido; não passa por
# `start`/`poll` — e lê o que o job publicou na conversa: o comparativo e a frase, nesta ordem.
# Desfazer a correção (voltar `partial_message` para a instância) faz este exemplo falhar — provado
# por mutação em 10/09/2026.
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
    # teste do comparativo ganha um endereço público, e o WebMock responde a chamada.
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
  end

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  # O PREÇO COMO O CLIENTE O LÊ, e o comparativo como o portal o entrega. Os dois são ENTREGAS: o
  # que o Arrange precisa montar não é "o handle diz que saiu", é a MENSAGEM na conversa — é ela
  # que o fecho consulta desde a entrega 8a.
  def preco_ao_cliente
    '*Ezze* — R$ 2.050,40 no total'
  end

  def comparativo_do_portal
    Autonomia::Agents::Tools::EntregaDeArquivo.new(
      url: 'https://exemplo.test/comparativo-mock.pdf',
      nome: 'Comparativo de seguro — placa ABC1D23.pdf',
      legenda: cotacao::Comparativo::LEGENDA,
      reserva: "#{cotacao::Comparativo::RESERVA}\nhttps://exemplo.test/comparativo-mock.pdf"
    )
  end

  def stub_comparativo_pdf
    stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf')
      .to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
  end

  # PUBLICA PELO CAMINHO REAL (o mesmo publicador do motor) e devolve o TOKEN da entrega — o que a
  # ferramenta grava no handle na passada que a emite. Levanta se a publicação não entrar: um
  # Arrange que mente sobre o que o cliente recebeu não prova nada.
  def publicar!(run, entrega)
    resultado = Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
    raise "o Arrange nao publicou a entrega: #{resultado.status}" unless resultado.published?

    Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
  end

  def abrir_execucao
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run
  end

  # A execução no estado em que o defeito aparecia: submetida, com um preço QUE O CLIENTE RECEBEU
  # (mensagem na conversa, contada na linha) e com o prazo vencido — como em 08/09/2026, quando
  # cinco preços chegaram e a conversa parou.
  def cotacao_com_preco_entregue_e_prazo_vencido
    run = abrir_execucao
    token = publicar!(run, preco_ao_cliente)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], cotacao::PRECOS_KEY => [token],
                                  'produto' => 'auto' })
    run
  end

  # O MESMO HANDLE, SEM MENSAGEM NENHUMA: o publicador recusou o preço (conversa encerrada, agente
  # desligado no meio, erro transitório) e o handle avançou assim mesmo — `deliver` roda ANTES de
  # `record_attempt!`, e o contador só sobe quando a publicação é aceita. É o estado em que o fecho
  # que perguntava ao handle afirmava "os preços acima são os que chegaram" sem nada acima.
  def cotacao_com_preco_no_handle_e_nada_na_conversa
    run = abrir_execucao
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], 'produto' => 'auto',
                                  cotacao::PRECOS_KEY => [Autonomia::Agents::Tools::EntregaPublicada
                                    .token_de(run, preco_ao_cliente)] })
    run
  end

  # A MESMA execução, sem preço nenhum: submetida, prazo vencido, nada entregue.
  def cotacao_sem_preco_e_prazo_vencido
    run = abrir_execucao
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1', 'produto' => 'auto' })
    run
  end

  # O PORTAL JÁ TINHA FECHADO E O COMPARATIVO JÁ TINHA SAÍDO — só o `finish!('done')` não chegou a
  # rodar. `build_progress` grava `comparativo_enviado` no ramo `done` e o `record_attempt!` o
  # persiste; o `finish_done` vem DEPOIS. Morto o worker entre os dois (deploy, hard shutdown do
  # Sidekiq), a linha fica `running` com tudo já entregue ao cliente.
  def cotacao_fechada_no_portal_com_a_linha_abandonada
    run = abrir_execucao
    stub_comparativo_pdf
    preco = publicar!(run, preco_ao_cliente)
    run.record_delivery!
    comparativo = publicar!(run, comparativo_do_portal)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], cotacao::PDF_SENT_KEY => true,
                                  cotacao::FECHADO_KEY => true, cotacao::PRECOS_KEY => [preco],
                                  cotacao::COMPARATIVO_KEY => comparativo, 'produto' => 'auto' })
    run
  end

  # O que o cliente já tinha na tela ANTES do encerramento, nesse estado.
  def tela_de_quem_recebeu_tudo
    [preco_ao_cliente, cotacao::Comparativo::LEGENDA]
  end

  # A FRASE PARCIAL NÃO SAI PARA QUEM RECEBEU TUDO, PELAS DUAS PORTAS DE ENCERRAMENTO.
  #
  # O fecho da cotação afirmava "sempre sobra, por construção", e a construção mentia: com
  # `comparativo_enviado` no handle, o cliente tem os preços E o comparativo, e "algumas seguradoras
  # não responderam a tempo" descreve uma tela que ele não está vendo. O silêncio é a resposta certa
  # — ele já tem tudo, e não há nada de novo a dizer.
  it 'a cotacao que ja entregou tudo fecha em silencio quando o prazo estoura' do
    # Arrange
    run = cotacao_fechada_no_portal_com_a_linha_abandonada

    # Act — a porta do MOTOR (`fail_run`)
    described_class.new.perform(run.id, 5)

    # Assert — nem frase parcial, nem comparativo repetido, nem chamada nova ao portal: a tela do
    # cliente é a mesma de antes do encerramento
    expect(bot_contents).to eq(tela_de_quem_recebeu_tudo)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  it 'o varredor tambem fecha em silencio a cotacao que ja entregou tudo' do
    # Arrange
    run = cotacao_fechada_no_portal_com_a_linha_abandonada
    run.update!(expires_at: 10.minutes.ago)

    # Act — a porta do VARREDOR (`ReapStaleRunsJob`)
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq(tela_de_quem_recebeu_tudo)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  # O HANDLE É A INTENÇÃO; A MENSAGEM É O FATO (P1 do verificador cego, 12/09/2026). Com
  # `entregues` no handle e NENHUMA mensagem na conversa, o fecho que perguntava ao handle mandava
  # o motor gerar o comparativo — login mais uma chamada de até 60 s ao portal — e ainda publicava
  # "algumas seguradoras não responderam a tempo, os preços acima são os que chegaram" sem nada
  # acima. Na `main`, esse estado lia a frase honesta de falha, que é o que ele volta a ler.
  #
  # O PORTAL NÃO É CHAMADO, e este exemplo o prova por construção: o PDF do conector `mock` não
  # está stubbado aqui, então qualquer pedido de comparativo acrescentaria uma mensagem (o link de
  # reserva) à lista abaixo.
  it 'a cotacao cujo preco nunca chegou ao cliente fecha com a frase de falha, e nao pede comparativo' do
    # Arrange
    run = cotacao_com_preco_no_handle_e_nada_na_conversa

    # Act
    described_class.new.perform(run.id, 5)

    # Assert
    expect(bot_contents).to eq([cotacao.failure_message])
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado', delivered_count: 0)
  end

  # NÃO-REGRESSÃO DA COTAÇÃO (Codex, P2). O `fail_run` deixou de filtrar por `delivered_count` e
  # passou a oferecer o encerramento à ferramenta SEMPRE — era o único jeito de um arquivo já gerado
  # sair quando o prazo estoura antes da primeira entrega. A cotação se protege
  # sozinha: `comparison_pdf` devolve nil sem `entregues` no handle, então a execução que morre sem
  # preço nenhum continua fechando com a frase de falha, sem comparativo e sem pedir nada ao portal
  # (se pedisse, o PDF do conector `mock` não está stubbado neste exemplo e a mensagem seria outra).
  it 'a cotacao que morre sem preco nenhum nao passa a mandar comparativo' do
    # Arrange
    run = cotacao_sem_preco_e_prazo_vencido

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — uma mensagem só, a de falha; nada do comparativo
    expect(bot_contents).to eq([cotacao.failure_message])
    expect(bot_contents).not_to include(cotacao::Comparativo::LEGENDA)
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', delivered_count: 0)
  end

  # O VARREDOR NÃO PEDE O COMPARATIVO AO PORTAL , e aqui pelo caminho REAL: a mesma
  # cotação abandonada, fechada pelo `ReapStaleRunsJob`. Gerar o comparativo é login mais uma chamada
  # de até 60 s, e o varredor processa até 500 linhas em sequência num cron com 25 s de shutdown —
  # morto no meio, a linha em curso fica com a marca `closed` e sem fecho, para sempre. O cliente
  # continua com os preços que leu e recebe o fecho honesto. (O PDF do conector `mock` não está
  # stubbado neste exemplo: se ele fosse pedido, sairia o link de reserva e este exemplo cairia.)
  it 'o varredor fecha a cotacao abandonada sem pedir o comparativo ao portal' do
    # Arrange
    run = cotacao_com_preco_entregue_e_prazo_vencido
    run.update!(expires_at: 10.minutes.ago)

    # Act
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::PARCIAL])
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  it 'publica a frase de SEGURADORAS quando o prazo estoura com preço ja entregue' do
    # Arrange — o comparativo do conector `mock` responde como PDF (entrega 11: sai como arquivo)
    run = cotacao_com_preco_entregue_e_prazo_vencido
    stub_comparativo_pdf

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — o preço que o cliente já tinha, depois o comparativo (o que ainda vale entregar) e
    # por fim o fecho DA COTAÇÃO
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::Comparativo::LEGENDA, cotacao::PARCIAL])
    expect(bot_contents.last).to include('seguradoras')
    expect(bot_contents.join(' ')).not_to include('consultas')
    expect(run.reload.status).to eq('failed')
  end
end
