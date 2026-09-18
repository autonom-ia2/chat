require 'rails_helper'

# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8b do Agente de Cotação, #459): ferramenta síncrona da Lia que acha a
# cotação da conversa, casa o nome que o cliente disse com o resultado guardado, pede ao portal o PDF daquela
# seguradora (`quote/proposal` com `insurerCode`) e o publica como ANEXO, sem legenda. O texto ao cliente é da Lia:
# ao modelo volta só o que aconteceu. Dados sintéticos; o portal é o `Connector::Mock`.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuoteProposal do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 90) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:connector) { Autonomia::Insurance::Connector.client }
  let(:pdf) { "%PDF-1.4\n%%EOF\n" }
  let(:ofertas) do
    [cotou('8', 'Porto Seguro', 2119.18), cotou('44', 'Usebens', 1647.82),
     { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'declined' }]
  end

  before do
    enable_test_encryption!
    conexao_pronta
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_proposal).and_call_original
    # O `SafeFetch` resolve o nome antes de conectar: o host do mock ganha um endereço público, e o WebMock responde.
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
    stub_request(:get, %r{\Ahttps://exemplo\.test/proposta-\d+-mock\.pdf\z})
      .to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  def cotou(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def conexao_pronta
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
  end

  # A cotação desta conversa, encerrada, com o resultado guardado de `ofertas`.
  def cotacao_da_conversa(status: 'done', argumentos: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'hik-9383' } })
    guardado = Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas)
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: status,
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                       agent_inbox_id: agent_inbox.id, arguments: argumentos,
                                       handle: { 'quote_id' => 'q-1:1', cotacao::RESULTADO_KEY => guardado })
  end

  def pedir(seguradora, turno: delivery)
    described_class.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: turno).call
  end

  def mensagens_do_bot
    conversation.messages.where(sender_type: 'AgentBot').order(:id)
  end

  it 'é síncrona e está no catálogo' do
    expect(described_class.async?).to be(false)
    expect(Autonomia::Agents::Tools::Registry.find('enviar_proposta_da_seguradora')).to eq(described_class)
  end

  describe 'a seguradora fez proposta' do
    it 'pelo nome exato, pede ao portal a proposta daquela seguradora e publica o PDF como anexo, sem legenda' do
      cotacao_da_conversa

      ao_modelo = pedir('Usebens')

      expect(connector).to have_received(:quote_proposal)
        .with(provider: anything, session: anything, quote_id: 'q-1:1', insurer_code: '44').once
      mensagem = mensagens_do_bot.sole
      expect(mensagem.content.to_s).to be_empty
      anexo = mensagem.attachments.sole
      expect(anexo.file.filename.to_s).to eq('Proposta Usebens, placa HIK9383.pdf')
      expect(anexo.file.download).to eq(pdf)
      expect(ao_modelo).to include('Usebens', 'enviada')
      expect(ao_modelo).not_to include('http', 'R$', '—')
    end

    it 'pelo nome parcial, em minúsculas e sem acento: "porto" é a Porto Seguro' do
      cotacao_da_conversa

      ao_modelo = pedir('porto')

      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '8')).once
      expect(mensagens_do_bot.sole.attachments.sole.file.filename.to_s).to eq('Proposta Porto Seguro, placa HIK9383.pdf')
      expect(ao_modelo).to include('Porto Seguro')
    end

    it 'sem placa, o nome do arquivo leva o ramo' do
      cotacao_da_conversa(argumentos: { 'produto' => 'residencial' })

      pedir('Usebens')

      expect(mensagens_do_bot.sole.attachments.sole.file.filename.to_s).to eq('Proposta Usebens, residencial.pdf')
    end

    it 'duas seguradoras são duas chamadas: dois arquivos, e nenhuma cotação nova é aberta' do
      cotacao_da_conversa

      expect do
        pedir('Porto')
        pedir('Usebens')
      end.not_to change(Autonomia::Agents::ToolRun, :count)

      expect(mensagens_do_bot.map { |m| m.attachments.sole.file.filename.to_s })
        .to eq(['Proposta Porto Seguro, placa HIK9383.pdf', 'Proposta Usebens, placa HIK9383.pdf'])
      expect(connector).to have_received(:quote_proposal).twice
    end
  end

  describe 'o nome não casa com uma seguradora só' do
    it 'inexistente: devolve os nomes de quem fez proposta, sem valor, e não pede nada ao portal' do
      cotacao_da_conversa

      ao_modelo = pedir('Bradesco')

      expect(ao_modelo).to include('Porto Seguro', 'Usebens')
      expect(ao_modelo).not_to include('Sancor', 'R$', '2.119', '1.647')
      expect(connector).not_to have_received(:quote_proposal)
      expect(mensagens_do_bot).to be_empty
    end

    it 'ambíguo (mais de uma casa): devolve a lista para o modelo perguntar' do
      cotacao_da_conversa

      ao_modelo = pedir('Porto ou Usebens')

      expect(ao_modelo).to include('Porto Seguro', 'Usebens')
      expect(connector).not_to have_received(:quote_proposal)
      expect(mensagens_do_bot).to be_empty
    end
  end

  describe 'não há proposta daquela seguradora' do
    it 'sem_proposta: diz ao modelo que ela não fez proposta, sem pedir ao portal' do
      cotacao_da_conversa

      ao_modelo = pedir('Sancor')

      expect(ao_modelo).to include('Sancor não fez proposta')
      expect(connector).not_to have_received(:quote_proposal)
      expect(mensagens_do_bot).to be_empty
    end

    it 'o adapter recusa ("no quoted insurer to print"): o mesmo texto de quem não fez proposta' do
      cotacao_da_conversa
      allow(connector).to receive(:quote_proposal)
        .and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'no quoted insurer to print'))

      ao_modelo = pedir('Usebens')

      expect(ao_modelo).to include('Usebens não fez proposta')
      expect(mensagens_do_bot).to be_empty
    end

    it 'sem cotação na conversa: diz que não há cotação' do
      expect(pedir('Usebens')).to eq(described_class::SEM_COTACAO)
    end
  end

  describe 'a proposta não pôde ser gerada ou baixada' do
    it 'download que falha: nada é publicado, e nem o texto ao modelo nem o log levam a URL' do
      cotacao_da_conversa
      stub_request(:get, 'https://exemplo.test/proposta-44-mock.pdf')
        .to_return(status: 404, body: '<Error><Code>BlobNotFound</Code></Error>', headers: { 'Content-Type' => 'application/xml' })
      allow(Rails.logger).to receive(:warn).and_call_original

      ao_modelo = pedir('Usebens')

      expect(ao_modelo).to include('Não deu para gerar a proposta da Usebens agora')
      expect(ao_modelo).not_to include('http', 'exemplo.test')
      expect(mensagens_do_bot).to be_empty
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('exemplo.test'))
    end

    it 'o portal falha: registra a CLASSE do erro, nunca a mensagem' do
      cotacao_da_conversa
      allow(connector).to receive(:quote_proposal)
        .and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'https://portal.test/segredo'))
      allow(Rails.logger).to receive(:warn).and_call_original

      ao_modelo = pedir('Usebens')

      expect(ao_modelo).to include('Não deu para gerar a proposta da Usebens agora')
      expect(Rails.logger).to have_received(:warn).with(a_string_including('Autonomia::Insurance::Connector::Error'))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('portal.test'))
    end

    it 'sem sessão viva no portal: não abre login dentro do turno, e diz que não deu agora' do
      cotacao_da_conversa
      Autonomia::Insurance::Connection.find_by(account: account).update!(session_expires_at: 1.minute.ago)

      ao_modelo = pedir('Usebens')

      expect(ao_modelo).to include('Não deu para gerar a proposta da Usebens agora')
      expect(connector).not_to have_received(:quote_proposal)
    end
  end

  it 'sem contexto de entrega (Testar, Copiloto): erro nomeado, e nada ao portal' do
    cotacao_da_conversa

    saida = described_class.new(agent: agent, params: { 'seguradora' => 'Usebens' }).call

    expect(JSON.parse(saida)).to eq('error' => 'lista_indisponivel_nesta_superficie')
    expect(connector).not_to have_received(:quote_proposal)
  end

  # O AGENTE QUE JÁ EXISTE (agente 24 da conta 16) recebe a ferramenta pela lista do deploy
  # (`Builder.ferramentas_mantidas`), sem escrita no banco: a coluna gravada no nascimento não a tem.
  it 'chega ao Agente de Cotação já criado, cuja coluna native_tool_slugs não a tem' do
    lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Corretora').call
    lia.update!(config: lia.config.merge('native_tool_slugs' => %w[consultar_produtos_cotacao ver_resultado_da_cotacao]))

    expect(Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_PRINCIPAL).to include(described_class.slug)
    expect(Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_ESPECIALISTA).not_to include(described_class.slug)
    expect(Autonomia::Agents::Tools::Bound.for_agent(lia.reload).map(&:slug)).to include(described_class.slug)
    expect(lia.reload.native_tool_slugs).not_to include(described_class.slug)
  end
end
