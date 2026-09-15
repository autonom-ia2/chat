require 'rails_helper'

# O LOTE DE PREÇOS DA COTAÇÃO AINDA A CAMINHO E A LISTA DA LIA, PELO CAMINHO REAL (quarta rodada de revisão da fatia
# 2 do #420). A cotação é despachada no turno de uma mensagem cuja entrega humanizada ficou aberta (dois pedaços
# esperados, nenhum postado: o cliente escreveu no meio), e o lote de preços dela fica adiado. O cliente pergunta
# quanto deu nesse intervalo. Caminho real: agente do `Builder`, `AsyncRunJob` da cotação, `Operate::Responder` com a
# ferramenta síncrona da Lia e a lista anexada ao turno (desenho da rodada 8), `AsyncPublishJob`. Dublados: o modelo e a
# leitura do portal. Dados sintéticos.
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
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:ferramenta) { Autonomia::Agents::Tools::Native::InsuranceQuoteResult }
  let(:motor) { Autonomia::Agents::Tools::AsyncRunJob }
  let(:portal) { Autonomia::Insurance::Connector::Mock.new }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true', INSURANCE_CONNECTOR_MODE: 'mock',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    enable_test_encryption!
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    conexao.update!(status: 'ready')
    conexao.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(portal)
    agente.update!(config: agente.config.merge('with_knowledge' => false))
    agent_inbox
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    allow(portal).to receive(:quote_result).and_return(
      { 'quote_id' => 'q-1:1', 'status' => 'partial',
        'offers' => [oferta('8', 'Porto Seguro', 2119.18), oferta('20', 'Allianz', 2323.17),
                     { 'insurer' => { 'code' => '47', 'name' => 'Sancor' }, 'status' => 'running' }] }
    )
  end

  def oferta(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def mensagem_do_cliente(texto)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
  end

  # A cotação despachada no turno de `origem`, com a entrega humanizada daquele turno esperando dois pedaços.
  def cotacao_despachada(origem, pedacos:)
    run = Autonomia::Agents::ToolRun.open!(agent: agente, slug: cotacao.slug, pedido: 'pedido-sintetico',
                                           arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                                    origin_message_id: origem.id })
    run.promote!(expected_chunks: pedacos, notify_customer: false, expires_at: 5.minutes.from_now)
    run.record_attempt!(handle: { motor::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1', cotacao::DELIVERED_KEY => [], 'produto' => 'auto' })
    run
  end

  # O modelo dublado: chama a ferramenta da Lia com `seguradora` e fala `texto`. -> o que a ferramenta devolveu.
  def modelo(seguradora, texto:)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    capturado = {}
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      chamada = { 'name' => ferramenta.slug, 'call_id' => 'c1', 'arguments' => { 'seguradora' => seguradora }.to_json }
      capturado[:saida] = executor&.call([chamada])&.first&.dig(:output)
      { text: { reply: texto, confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    capturado
  end

  def turno_da_lia(mensagem)
    Autonomia::Agents::Operate::Responder.new(conversation: conversation.reload, agent_inbox: agent_inbox,
                                              reply_to_message_id: mensagem.id).perform
  end

  def lote_adiado(run)
    job = enqueued_jobs.reverse.find do |item|
      item[:job] == Autonomia::Agents::Tools::AsyncPublishJob && ActiveJob::Arguments.deserialize(item[:args])[0] == run.id
    end
    ActiveJob::Arguments.deserialize(job[:args])
  end

  def vezes(nome)
    conversation.messages.reload.where(sender_type: 'AgentBot').sum { |mensagem| mensagem.content.to_s.scan("*#{nome}*").size }
  end

  it 'com o lote adiado, a Lia ouve que os preços estão sendo enviados, não anexa lista, e cada preço sai uma vez' do
    cotacao_run = cotacao_despachada(mensagem_do_cliente('quero cotar'), pedacos: 2)
    motor.new.perform(cotacao_run.id, 1)
    adiado = lote_adiado(cotacao_run)
    expect(conversation.messages.where(sender_type: 'AgentBot')).to be_empty

    capturado = modelo(nil, texto: 'Os preços estão chegando.')
    turno_da_lia(mensagem_do_cliente('quanto deu?'))
    Autonomia::Agents::Tools::AsyncPublishJob.new.perform(cotacao_run.id, adiado[1], Autonomia::Agents::Tools::AsyncConfig::MAX_PUBLISH_DEFERRALS)

    expect(capturado[:saida]).to end_with(ferramenta::PRECOS_A_CAMINHO)
    expect(Autonomia::Agents::ToolRun.where(slug: ferramenta.slug)).to be_empty
    expect([vezes('Porto Seguro'), vezes('Allianz')]).to eq([1, 1])
  end

  it 'com o lote adiado e a pergunta por uma seguradora, o modelo ouve que o preço dela está sendo enviado' do
    cotacao_run = cotacao_despachada(mensagem_do_cliente('quero cotar'), pedacos: 2)
    motor.new.perform(cotacao_run.id, 1)
    adiado = lote_adiado(cotacao_run)

    capturado = modelo('Porto', texto: 'O da Porto está chegando.')
    turno_da_lia(mensagem_do_cliente('e a Porto?'))
    Autonomia::Agents::Tools::AsyncPublishJob.new.perform(cotacao_run.id, adiado[1], Autonomia::Agents::Tools::AsyncConfig::MAX_PUBLISH_DEFERRALS)

    expect(capturado[:saida]).to include('Porto Seguro fez proposta: o preço dela está na fila de envio e chega numa mensagem do sistema.')
    expect(vezes('Porto Seguro')).to eq(1)
  end

  # O LOTE PUBLICADO NA HORA COM A FILA DE ENVIO FORA (quinta rodada de revisão): a mensagem fica com pendência de envio
  # e sem aceite, e o varredor ainda a reenvia. A Lia não repete o preço.
  it 'com o lote publicado e o envio pendente, a Lia ouve que os preços estão na fila, e o preço sai uma vez' do
    cotacao_run = cotacao_despachada(mensagem_do_cliente('quero cotar'), pedacos: 0)
    fila_recusa_o_envio
    motor.new.perform(cotacao_run.id, 1)
    fila_volta
    expect(conversation.messages.where(sender_type: 'AgentBot').map { |mensagem| mensagem.content_attributes['autonomia_envio_pendente'] })
      .to eq([true])

    capturado = modelo(nil, texto: 'Os preços estão chegando.')
    turno_da_lia(mensagem_do_cliente('quanto deu?'))

    expect(capturado[:saida]).to end_with(ferramenta::PRECOS_A_CAMINHO)
    expect([vezes('Porto Seguro'), vezes('Allianz')]).to eq([1, 1])
  end

  # A PUBLICAÇÃO ADIADA QUE MORREU (quinta rodada de revisão): passada a janela do lote, a Lia volta a anexar a lista,
  # e o cliente recebe os preços.
  it 'com o lote aceito que nunca virou mensagem, passada a janela, a lista da Lia sai' do
    cotacao_run = cotacao_despachada(mensagem_do_cliente('quero cotar'), pedacos: 2)
    motor.new.perform(cotacao_run.id, 1)
    lote_adiado(cotacao_run)

    travel(Autonomia::Insurance::ResultadoDaCotacao::JANELA_DO_LOTE + 1.minute) do
      capturado = modelo(nil, texto: 'Seguem os preços.')
      turno_da_lia(mensagem_do_cliente('quanto deu?'))

      expect(capturado[:saida]).to include(ferramenta::LISTA_ANEXADA)
      expect([vezes('Porto Seguro'), vezes('Allianz')]).to eq([1, 1])
    end
  end

  # O CONTROLE: com o lote já entregue, o cliente que pede os preços de novo recebe a lista.
  it 'com o lote já entregue, a lista da Lia sai' do
    cotacao_run = cotacao_despachada(mensagem_do_cliente('quero cotar'), pedacos: 0)
    motor.new.perform(cotacao_run.id, 1)
    expect([vezes('Porto Seguro'), vezes('Allianz')]).to eq([1, 1])

    capturado = modelo(nil, texto: 'Seguem de novo.')
    turno_da_lia(mensagem_do_cliente('manda de novo'))

    expect(capturado[:saida]).to include(ferramenta::LISTA_ANEXADA)
    expect([vezes('Porto Seguro'), vezes('Allianz')]).to eq([2, 2])
  end
end
