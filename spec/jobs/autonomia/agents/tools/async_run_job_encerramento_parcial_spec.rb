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

  # A execução no estado em que o defeito aparecia: submetida, com um preço contado como entregue,
  # e com o prazo vencido — como em 08/09/2026, quando cinco preços chegaram e a conversa parou.
  def cotacao_com_preco_entregue_e_prazo_vencido
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], 'produto' => 'auto' })
    run.record_delivery!
    run
  end

  # A MESMA execução, sem preço nenhum: submetida, prazo vencido, nada entregue.
  def cotacao_sem_preco_e_prazo_vencido
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1', 'produto' => 'auto' })
    run
  end

  # O PORTAL JÁ TINHA FECHADO E O COMPARATIVO JÁ TINHA SAÍDO — só o `finish!('done')` não chegou a
  # rodar. `build_progress` grava `comparativo_enviado` no ramo `done` e o `record_attempt!` o
  # persiste; o `finish_done` vem DEPOIS. Morto o worker entre os dois (deploy, hard shutdown do
  # Sidekiq), a linha fica `running` com tudo já entregue ao cliente.
  def cotacao_fechada_no_portal_com_a_linha_abandonada
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], cotacao::PDF_SENT_KEY => true,
                                  'produto' => 'auto' })
    run.record_delivery!
    run
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

    # Assert — nem frase parcial, nem comparativo repetido, nem chamada nova ao portal
    expect(bot_contents).to be_empty
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  it 'o varredor tambem fecha em silencio a cotacao que ja entregou tudo' do
    # Arrange
    run = cotacao_fechada_no_portal_com_a_linha_abandonada
    run.update!(expires_at: 10.minutes.ago)

    # Act — a porta do VARREDOR (`ReapStaleRunsJob`)
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to be_empty
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  # NÃO-REGRESSÃO DA COTAÇÃO (Codex, P2). O `fail_run` deixou de filtrar por
  # `delivered_count` e passou a oferecer o encerramento à ferramenta SEMPRE — era o único jeito de a
  # proposta já gerada sair quando o prazo estoura antes da primeira entrega. A cotação se protege
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

  # O VARREDOR NÃO PEDE O COMPARATIVO AO PORTAL (rodada 6, P2-E), e aqui pelo caminho REAL: a mesma
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
    expect(bot_contents).to eq([cotacao::PARCIAL])
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  it 'publica a frase de SEGURADORAS quando o prazo estoura com preço ja entregue' do
    # Arrange — o comparativo do conector `mock` responde como PDF (entrega 11: sai como arquivo)
    run = cotacao_com_preco_entregue_e_prazo_vencido
    stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf')
      .to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — primeiro o comparativo (o que ainda vale entregar), depois o fecho DA COTAÇÃO
    expect(bot_contents).to eq([cotacao::Comparativo::LEGENDA, cotacao::PARCIAL])
    expect(bot_contents.last).to include('seguradoras')
    expect(bot_contents.join(' ')).not_to include('consultas')
    expect(run.reload.status).to eq('failed')
  end
end
