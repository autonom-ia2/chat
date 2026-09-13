require 'rails_helper'

# NENHUM ESTADO FICA MUDO (entrega das frases do especialista, 12/09/2026).
#
# A exigência do CEO tem duas metades, e esta é a segunda: "não aceito regressão — todo estado que
# hoje produz palavra ao cliente continua produzindo". A primeira metade é a morte da frase parcial,
# e é ela que torna esta prova necessária: um papel que passasse a depender do modelo para existir
# seria um cliente esperando em silêncio no dia em que o modelo não escrevesse nada.
#
# CADA ESTADO É EXERCITADO PELO CAMINHO REAL, e sob as QUATRO formas em que o especialista pode
# falhar: execução aberta antes desta versão (sem o nó), nó vazio, frases em branco e frases que a
# peneira reprova. Em todas as quatro sai palavra.
module DesfalquesDoEspecialista
  # AS QUATRO FORMAS DE O ESPECIALISTA NÃO ESCREVER. `strict` garante a presença das quatorze
  # chaves, nunca o conteúdo delas — a garantia de que sai palavra é do código, não do modelo.
  FRASES = Autonomia::Agents::Tools::Native::InsuranceQuote::Frases
  NOMES = ['execução aberta antes desta versão (sem o nó)', 'nó vazio',
           'frases em branco', 'frases que a peneira reprova'].freeze

  module_function

  def argumentos(desfalque)
    case desfalque
    when 'nó vazio' then { FRASES::NO => {} }
    when 'frases em branco' then { FRASES::NO => todas('  ') }
    when 'frases que a peneira reprova' then { FRASES::NO => todas('Chegaram 3 opções — veja insured.document') }
    else {}
    end
  end

  def todas(texto)
    FRASES::ORDEM.index_with { texto }.transform_keys(&:to_s)
  end
end

RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:frases) { described_class::Frases }
  let(:base) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'TYV8I74' } } }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    quote_proposal: { 'url' => 'https://arquivos.exemplo.test/c-9.pdf' },
                    vehicle_lookup: { 'plate' => 'TYV8I74', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' })
  end

  def argumentos(desfalque)
    DesfalquesDoEspecialista.argumentos(desfalque)
  end

  def ferramenta(desfalque, extras = {})
    described_class.new(agent: agent, params: base.merge(extras).merge(argumentos(desfalque)))
  end

  def offer(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def consulta(status, offers)
    allow(connector).to receive(:quote_result).and_return({ 'quote_id' => 'abc:1', 'status' => status, 'offers' => offers })
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  DesfalquesDoEspecialista::NOMES.each do |desfalque|
    describe "com #{desfalque}" do
      # OS QUATRO TEXTOS DE CLASSE: o motor os publica sem instância — o aviso de espera na primeira
      # passada, os desfechos no encerramento, inclusive com o agente já apagado.
      it 'os quatro textos de classe saem' do
        args = argumentos(desfalque)

        expect(described_class.waiting_message(args)).to be_present
        expect(described_class.failure_message(args)).to be_present
        expect(described_class.uncertain_message(args)).to be_present
        expect(described_class.closing_message(args)).to be_present
      end

      it 'a recusa por JSON invalido pede palavra ao cliente' do
        tool = ferramenta(desfalque, 'dados' => 'isto não é json')

        expect(tool.start['pedido']).to be_present
      end

      it 'a recusa por falta de veiculo pede a placa' do
        tool = ferramenta(desfalque, 'vehicle' => {})

        expect(tool.start['pedido']).to be_present
      end

      it 'a recusa por formulario indisponivel fala' do
        Autonomia::Insurance::Connection.for_account(account).each { |c| c.update!(metadata: {}) }
        allow(connector).to receive(:quote_schema).and_return(nil)

        expect(ferramenta(desfalque).start['pedido']).to be_present
      end

      it 'a recusa por ramo desconhecido fala, com a lista de ramos' do
        allow(connector).to receive(:quote_validate)
          .and_raise(Autonomia::Insurance::Connector::Error.new(:not_implemented, 'sem ramo'))

        pedido = ferramenta(desfalque, 'produto' => 'nautico').start['pedido']

        expect(pedido).to be_present
        expect(pedido).to include('bicicleta')
      end

      # DOIS PAPÉIS NUM CAMINHO SÓ: com rótulo conhecido sai a abertura mais a lista; sem rótulo
      # conhecido sai o papel genérico. Nenhum dos dois pode calar.
      it 'o pedido do que falta fala, com e sem rotulo conhecido' do
        allow(connector).to receive(:quote_validate)
          .and_return({ 'valido' => false, 'problemas' => [{ 'campo' => 'insured.document', 'severidade' => 'erro', 'motivo' => 'x' }] })
        expect(ferramenta(desfalque).start['pedido']).to include('CPF do titular')

        allow(connector).to receive(:quote_validate)
          .and_return({ 'valido' => false, 'problemas' => [{ 'campo' => 'algo.desconhecido', 'severidade' => 'erro', 'motivo' => 'x' }] })
        expect(ferramenta(desfalque).start['pedido']).to be_present
      end

      it 'o primeiro lote de precos abre com palavra' do
        consulta('running', [offer('43', 'Ezze', 2050.40)])

        texto = ferramenta(desfalque).poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1).deliveries.sole

        expect(texto.lines.first.strip).to be_present
        expect(texto).to include('R$ 2.050,40')
      end

      it 'o lote seguinte de uma opcao abre com palavra, e sem numero' do
        consulta('running', [offer('43', 'Ezze', 2050.40), offer('3', 'Mapfre', 2582.76)])

        texto = ferramenta(desfalque).poll(handle: { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'] },
                                           attempt: 1).deliveries.sole

        expect(texto.lines.first.strip).to be_present
        expect(texto.lines.first).not_to match(/[0-9]/)
      end

      it 'o lote seguinte de varias opcoes abre com palavra, e sem numero' do
        consulta('running', [offer('43', 'Ezze', 2050.40), offer('3', 'Mapfre', 2582.76), offer('9', 'Darwin', 3407.87)])

        texto = ferramenta(desfalque).poll(handle: { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['43'] },
                                           attempt: 1).deliveries.sole

        expect(texto.lines.first.strip).to be_present
        expect(texto.lines.first).not_to match(/[0-9]/)
      end

      it 'o aviso de renovacao sem bonus sai junto do primeiro preco' do
        consulta('running', [offer('43', 'Ezze', 2050.40)])
        handle = { 'quote_id' => 'abc:1', described_class::SEM_BONUS_KEY => true }

        resultado = ferramenta(desfalque).poll(handle: handle, attempt: 1)

        expect(resultado.deliveries.sole.split("\n\n").last).to be_present
        expect(resultado.handle[described_class::AVISO_SENT_KEY]).to be(true)
      end

      it 'o comparativo sai com legenda e com reserva' do
        consulta('completed', [offer('43', 'Ezze', 2050.40)])

        entregas = ferramenta(desfalque).poll(handle: { 'quote_id' => 'abc:1' }, attempt: 1).deliveries
        arquivo = Autonomia::Agents::Tools::EntregaDeArquivo.de(entregas.last)

        expect(arquivo.legenda).to be_present
        expect(arquivo.reserva).to be_present
      end
    end
  end

  # OS ESTADOS NOVOS DA FATIA 1 DO PDF RÁPIDO (13/09/2026), pelo MOTOR. A cotação passa a encerrar em
  # `done` quando toda seguradora tem desfecho, e o comparativo que não sai ganha nova tentativa. Até
  # esta fatia o desfecho de toda cotação real saía pelo encerramento por prazo; estes exemplos provam
  # que cada estado novo ainda termina com palavra ao cliente, sob as mesmas quatro formas de o
  # especialista não escrever.
  describe 'os estados novos do encerramento sem esperar o portal' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agent_inbox) do
      Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
    end
    let(:mock) { Autonomia::Insurance::Connector::Mock.new }
    let(:url) { 'https://exemplo.test/comparativo-mock.pdf' }
    let(:job) { Autonomia::Agents::Tools::AsyncRunJob }

    around do |example|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
    end

    before do
      account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_enabled' => true))
      register_async_tool(described_class)
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(mock)
      allow(mock).to receive(:quote_proposal).and_call_original
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
    end

    def portal(status, ofertas)
      allow(mock).to receive(:quote_result).and_return({ 'quote_id' => 'q-1:1', 'status' => status, 'offers' => ofertas })
    end

    def recusa(code)
      { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => 'declined' }
    end

    # A execução depois de uma consulta que já listou as duas seguradoras.
    def execucao(desfalque, handle = {})
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug,
                                             arguments: base.merge(argumentos(desfalque)),
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
      run.record_attempt!(handle: { Autonomia::Agents::Tools::AsyncRunJob::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1',
                                    described_class::DELIVERED_KEY => [],
                                    described_class::ACIONADAS_KEY => %w[3 43],
                                    described_class::LEITURA_ASSENTADA_KEY => %w[3 43] }.merge(handle))
      run
    end

    def passadas(run, *tentativas)
      tentativas.each { |tentativa| job.new.perform(run.id, tentativa) }
      run.reload
    end

    def ultima_palavra
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).last&.content
    end

    DesfalquesDoEspecialista::NOMES.each do |desfalque|
      describe "com #{desfalque}" do
        it 'toda seguradora com desfecho e preco entregue: o done diz o fecho de quem tem resultado' do
          stub_request(:get, url).to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5)

          expect(run.status).to eq('done')
          expect(ultima_palavra).to be_present
          expect(ultima_palavra).to eq(described_class.closing_message(run.arguments))
        end

        it 'toda seguradora recusou: o done diz a frase de falha' do
          portal('running', [recusa('43'), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5)

          expect(run.status).to eq('done')
          expect(ultima_palavra).to be_present
          expect(ultima_palavra).to eq(described_class.failure_message(run.arguments))
        end

        it 'o comparativo que nao sai ate o teto: o done ainda diz o fecho' do
          allow(mock).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, '504'))
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5, 6, 7)

          expect(run.status).to eq('done')
          expect(ultima_palavra).to eq(described_class.closing_message(run.arguments))
        end

        it 'o download que falha ate o teto: o done diz o fecho, sem link' do
          stub_request(:get, url).to_return(status: 404, body: 'x')
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5, 6, 7, 8)

          expect(run.status).to eq('done')
          expect(ultima_palavra).to eq(described_class.closing_message(run.arguments))
          expect(conversation.messages.reload.map(&:content).join).not_to include(url)
        end

        it 'a passada done que morreu antes do desfecho: o varredor diz o fecho' do
          stub_request(:get, url).to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)
          morre = job.new
          allow(morre).to receive(:finish_done)
          morre.perform(run.id, 5)
          run.update!(expires_at: 10.minutes.ago)

          Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

          expect(run.reload.status).to eq('failed')
          expect(ultima_palavra).to eq(described_class.closing_message(run.arguments))
        end

        it 'a linha abandonada esperando nova tentativa do comparativo: o varredor diz o fecho' do
          allow(mock).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, '504'))
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)
          passadas(run, 5)
          run.update!(expires_at: 10.minutes.ago)

          Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

          expect(run.reload.status).to eq('failed')
          expect(ultima_palavra).to eq(described_class.closing_message(run.arguments))
        end
      end
    end
  end

  # OS ESTADOS NOVOS DA FATIA 2 DO #420: a cotação que pede a confirmação no intervalo curto, e a ferramenta
  # da Lia que mostra o resultado guardado. Na cotação, cada estado novo ainda termina com palavra ao cliente,
  # sob as quatro formas de o especialista não escrever. Na ferramenta da Lia, quem fala é a Lia: com preço, o
  # código publica os itens depois da fala dela; sem preço, o modelo recebe um texto para falar, em todo
  # estado. A ferramenta não publica frase pronta nenhuma (os textos de classe dela são vazios).
  describe 'os estados novos da fatia 2 (resultado guardado e ferramenta da Lia)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agent_inbox) do
      Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
    end
    let(:mock) { Autonomia::Insurance::Connector::Mock.new }
    let(:job) { Autonomia::Agents::Tools::AsyncRunJob }
    let(:resultado) { Autonomia::Agents::Tools::Native::InsuranceQuoteResult }

    around do |example|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
    end

    before do
      account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_enabled' => true))
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(mock)
      allow(mock).to receive(:quote_proposal).and_call_original
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
      stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf')
        .to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
    end

    def recusa(code)
      { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => 'declined' }
    end

    def cotacao_viva(desfalque)
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: base.merge(argumentos(desfalque)),
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
      run.record_attempt!(handle: { job::SUBMITTED_KEY => true, 'quote_id' => 'q-1:1', described_class::DELIVERED_KEY => [],
                                    described_class::ACIONADAS_KEY => %w[3 43] })
      run
    end

    def palavras_do_bot
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
    end

    DesfalquesDoEspecialista::NOMES.each do |desfalque|
      describe "com #{desfalque}" do
        it 'a primeira leitura com todas com desfecho pede a confirmacao logo, e o done seguinte diz o fecho' do
          register_async_tool(described_class)
          allow(mock).to receive(:quote_result)
            .and_return({ 'quote_id' => 'q-1:1', 'status' => 'partial', 'offers' => [offer('43', 'Ezze', 2050.40), recusa('3')] })
          run = cotacao_viva(desfalque)

          job.new.perform(run.id, 12)
          confirmacao = enqueued_jobs.find { |item| item[:job] == job && item[:args] == [run.id, 13] }
          job.new.perform(run.id, 13)

          expect(confirmacao[:at]).to be_within(2).of(3.seconds.from_now.to_f)
          expect(run.reload.status).to eq('done')
          expect(palavras_do_bot.last).to eq(described_class.closing_message(run.arguments))
        end

        # A ferramenta da Lia lê a cotação cuja chamada teve este desfalque: o que ela publica são os itens
        # do código, e nunca uma frase do especialista ou uma constante.
        it 'a ferramenta da Lia publica os itens de preco depois da fala, sem frase pronta' do
          fonte = cotacao_viva(desfalque)
          fonte.record_attempt!(handle: { described_class::RESULTADO_KEY =>
                                            Autonomia::Insurance::ResultadoPorSeguradora.unir({}, [offer('43', 'Ezze', 2050.40)]) })
          fonte.finish!('done')
          register_async_tool(resultado)
          exibicao = Autonomia::Agents::ToolRun.open!(agent: agent, slug: resultado.slug, arguments: { 'seguradora' => nil },
                                                      scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
          exibicao.promote!(expected_chunks: 0, notify_customer: true, expires_at: 5.minutes.from_now)

          job.new.perform(exibicao.id, 0)
          job.new.perform(exibicao.id, 1)

          expect(palavras_do_bot).to eq([Autonomia::Insurance::QuoteOffers.item(offer('43', 'Ezze', 2050.40))])
          expect(exibicao.reload.status).to eq('done')
        end
      end
    end

    # SEM PREÇO A PUBLICAR, QUEM FALA É A LIA, e ela recebe um texto em todo estado.
    it 'sem preco a publicar, o modelo recebe texto em todo estado da ferramenta da Lia' do
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 7)
      ao_modelo = ->(seguradora) { resultado.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: delivery).precheck.to_s }
      guardado = ->(ofertas) { { described_class::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) } }
      textos = [ao_modelo.call(nil)]

      run = cotacao_viva('nó vazio')
      textos << ao_modelo.call(nil)
      run.record_attempt!(handle: guardado.call([recusa('3')]))
      textos += [ao_modelo.call(nil), ao_modelo.call('Seguradora 3'), ao_modelo.call('Azul')]
      run.finish!('done')
      textos += [ao_modelo.call(nil), ao_modelo.call('Seguradora 3'), ao_modelo.call('Azul')]

      expect(textos.size).to eq(8)
      expect(textos).to all(be_present)
    end

    it 'os textos de classe da ferramenta da Lia sao vazios, com qualquer argumento' do
      DesfalquesDoEspecialista::NOMES.each do |desfalque|
        args = argumentos(desfalque)
        textos = %i[waiting_message failure_message uncertain_message partial_message closing_message]

        expect(textos.map { |texto| resultado.public_send(texto, args) }).to all(eq(''))
      end
    end
  end

  # A MORTE DA PARCIAL, DITA PELO QUE SAI NO LUGAR. A frase "algumas seguradoras não responderam a
  # tempo" deixa de existir para o cliente (decisão do CEO); o ESTADO que a produzia continua
  # falando, com um texto que não conta a nossa mecânica de leque.
  describe 'a morte da frase parcial' do
    it 'o estado que dizia a parcial agora diz o fecho de quem tem resultado' do
      expect(described_class.closing_message(nil)).to eq(described_class::Declaracao::FECHO_COM_RESULTADO)
      expect(described_class.closing_message(nil)).to be_present
      expect(described_class.closing_message(nil)).not_to eq(described_class::PARCIAL)
    end

    it 'o fecho novo nao conta ao cliente quantas seguradoras ficaram pelo caminho' do
      texto = described_class.closing_message(nil)

      expect(texto).not_to include('seguradoras')
      expect(texto).not_to match(/[0-9]/)
    end

    # ELA CONTINUA EXISTINDO NO CÓDIGO, e só por isto: a versão anterior a esta publica ESTE texto,
    # e o conjunto de perguntas do fecho precisa reconhecê-lo para o rollback não pôr dois desfechos
    # na mesma conversa (ver `Tools::Encerramento::FRASES_DE_FECHO`).
    it 'a constante parcial continua disponivel para a pergunta do rollback' do
      expect(described_class.partial_message).to eq(described_class::PARCIAL)
      expect(Autonomia::Agents::Tools::Encerramento::FRASES_DE_FECHO).to include(:partial_message, :closing_message)
    end
  end
end
