require 'rails_helper'

# NENHUM ESTADO FICA MUDO (entrega das frases do especialista, 12/09/2026; refeito na PR C).
#
# A exigência do CEO: "não aceito regressão — todo estado que hoje produz palavra ao cliente continua
# produzindo". Desde a PR C a palavra não é mais frase nossa nem frase que o especialista escrevia no pedido: é a
# Lia, num turno de modelo acionado por um EVENTO. O que este arquivo prova é que CADA estado que falava continua
# disparando um evento (e com fatos para o modelo), pelo caminho real, e que nenhum deles publica texto pronto.
#
# DUAS FORMAS DE EXECUÇÃO: a nova, e a aberta antes da PR C, que traz o nó `frases_ao_cliente` nos argumentos
# (e às vezes frases que a peneira antiga reprovaria). As duas seguem pelo caminho novo.
module ExecucoesDaCotacao
  NOMES = ['execução nova', 'execução anterior à PR C, com as frases no pedido'].freeze
  FRASES_ANTIGAS = { 'espera' => 'Estou vendo isso pra você.', 'falhou' => 'Não deu agora — veja insured.document',
                     'comparativo_legenda' => 'Segue o comparativo.' }.freeze

  module_function

  def argumentos(forma)
    forma == NOMES.last ? { 'frases_ao_cliente' => FRASES_ANTIGAS } : {}
  end
end

RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:base) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'TYV8I74' } } }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    quote_proposal: { 'url' => 'https://arquivos.exemplo.test/c-9.pdf' },
                    vehicle_lookup: { 'plate' => 'TYV8I74', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' })
  end

  def argumentos(desfalque)
    ExecucoesDaCotacao.argumentos(desfalque)
  end

  # Os fatos que o modelo lê no evento desta recusa (PR C).
  def fatos(tipo, handle)
    described_class.fatos_do_evento(tipo, Autonomia::Agents::ToolRun.new(handle: handle))
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

  ExecucoesDaCotacao::NOMES.each do |desfalque|
    describe "com #{desfalque}" do
      # CADA RECUSA DO ENVIO VIRA O SEU EVENTO, com fatos para o modelo, e nenhum texto ao cliente no handle.
      it 'a recusa por JSON invalido vira falta de dado' do
        handle = ferramenta(desfalque, 'dados' => 'isto não é json').start

        expect(handle).not_to have_key('pedido')
        expect(fatos('falta_dado', handle)).to be_present
      end

      it 'a recusa por falta de veiculo vira falta de dado, com a placa nos fatos' do
        handle = ferramenta(desfalque, 'vehicle' => {}).start

        expect(handle['recusa']).to eq('sem_veiculo')
        expect(fatos('falta_dado', handle)).to include('placa')
      end

      it 'a recusa por formulario indisponivel vira falha' do
        Autonomia::Insurance::Connection.for_account(account).each { |c| c.update!(metadata: {}) }
        allow(connector).to receive(:quote_schema).and_return(nil)
        tool = ferramenta(desfalque)

        expect(tool.poll(handle: tool.start, attempt: 1).evento).to eq('falhou')
      end

      it 'a recusa por ramo desconhecido vira o seu evento, com a lista de ramos nos fatos' do
        allow(connector).to receive(:quote_validate)
          .and_raise(Autonomia::Insurance::Connector::Error.new(:not_implemented, 'sem ramo'))
        tool = ferramenta(desfalque, 'produto' => 'nautico')
        handle = tool.start

        expect(tool.poll(handle: handle, attempt: 1).evento).to eq('ramo_desconhecido')
        expect(fatos('ramo_desconhecido', handle)).to include('bicicleta')
      end

      # O QUE FALTA, COM E SEM RÓTULO CONHECIDO: os dois viram falta de dado, com o campo nos fatos.
      it 'o pedido do que falta vira falta de dado, com e sem rotulo conhecido' do
        allow(connector).to receive(:quote_validate)
          .and_return({ 'valido' => false, 'problemas' => [{ 'campo' => 'insured.document', 'severidade' => 'erro', 'motivo' => 'x' }] })
        expect(fatos('falta_dado', ferramenta(desfalque).start)).to include('CPF do titular')

        allow(connector).to receive(:quote_validate)
          .and_return({ 'valido' => false, 'problemas' => [{ 'campo' => 'algo.desconhecido', 'severidade' => 'erro', 'motivo' => 'x' }] })
        expect(fatos('falta_dado', ferramenta(desfalque).start)).to include('algo.desconhecido')
      end

      # O AVISO DA RENOVAÇÃO SEM BÔNUS vai nos fatos da conclusão; o comparativo sai sem texto.
      it 'o comparativo sai sem texto, e o aviso de renovacao sem bonus vai nos fatos da conclusao' do
        consulta('completed', [offer('43', 'Ezze', 2050.40)])
        handle = { 'quote_id' => 'abc:1', described_class::SEM_BONUS_KEY => true }

        entregas = ferramenta(desfalque).poll(handle: handle, attempt: 1).deliveries

        expect(entregas.sole['arquivo'].keys).to eq(%w[url nome])
        expect(fatos('concluida', handle)).to include('classe de bônus')
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

    def textos_na_conversa
      conversation.messages.reload.where(sender_type: 'AgentBot').filter_map { |m| m.content.presence }
    end

    ExecucoesDaCotacao::NOMES.each do |desfalque|
      describe "com #{desfalque}" do
        it 'toda seguradora com desfecho e preco entregue: o comparativo, e a conclusao' do
          stub_request(:get, url).to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5)

          expect(run.status).to eq('done')
          expect(eventos_disparados(run)).to eq(['concluida'])
          expect(textos_na_conversa).to be_empty
        end

        it 'toda seguradora recusou: o done dispara a falha' do
          portal('running', [recusa('43'), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5)

          expect(run.status).to eq('done')
          expect(eventos_disparados(run)).to eq(['falhou'])
          expect(textos_na_conversa).to be_empty
        end

        # O PDF QUE NÃO SAI (fatia 3 do #420): sem lote de preço, o cliente não tem valor nenhum na tela, e o
        # desfecho é o dos valores guardados.
        it 'o comparativo que nao sai ate o teto: o done dispara os valores guardados' do
          allow(mock).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, '504'))
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5, 6, 7)

          expect(run.status).to eq('done')
          expect(eventos_disparados(run)).to eq(['valores_guardados'])
        end

        it 'o download que falha ate o teto: o done dispara os valores guardados, sem link' do
          stub_request(:get, url).to_return(status: 404, body: 'x')
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)

          passadas(run, 5, 6, 7, 8)

          expect(run.status).to eq('done')
          expect(eventos_disparados(run)).to eq(['valores_guardados'])
          expect(conversation.messages.reload.map(&:content).join).not_to include(url)
        end

        it 'a passada done que morreu depois do comparativo: o varredor dispara a conclusao que faltou' do
          stub_request(:get, url).to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)
          morre = job.new
          allow(morre).to receive(:finish_done)
          morre.perform(run.id, 5)
          run.update!(expires_at: 10.minutes.ago)

          Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

          expect(run.reload.status).to eq('failed')
          expect(eventos_disparados(run)).to eq(['concluida'])
          expect(textos_na_conversa).to be_empty
        end

        it 'a linha abandonada esperando nova tentativa do comparativo: o varredor dispara os valores guardados' do
          allow(mock).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:timeout, '504'))
          portal('partial', [offer('43', 'Ezze', 2050.40), recusa('3')])
          run = execucao(desfalque)
          passadas(run, 5)
          run.update!(expires_at: 10.minutes.ago)

          Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

          expect(run.reload.status).to eq('failed')
          expect(eventos_disparados(run)).to eq(['valores_guardados'])
        end

        # SEM SINAL DE VIDA (chat#585, decisão do CEO em 22/09/2026): a cotação que passa de dois minutos não fala
        # sozinha. Quem pergunta é respondido pela Lia, pelo especialista e o resultado parcial.
        it 'a cotacao que passa de dois minutos sem terminar nao fala sozinha' do
          portal('running', [offer('43', 'Ezze', 2050.40)])
          run = execucao(desfalque)
          run.update_columns(created_at: 121.seconds.ago) # rubocop:disable Rails/SkipsModelValidations

          passadas(run, 5, 6)

          expect(run.status).to eq('running')
          expect(conversation.messages.reload.where(sender_type: 'AgentBot').map(&:content)).to be_empty
          expect(eventos_disparados(run)).to be_empty
        end
      end
    end
  end

  # OS ESTADOS NOVOS DA FATIA 2 DO #420: a cotação que pede a confirmação no intervalo curto, e a ferramenta
  # da Lia que mostra o resultado guardado. Na cotação, cada estado novo ainda termina com palavra ao cliente,
  # sob as quatro formas de o especialista não escrever. Na ferramenta da Lia, quem fala é a Lia: com preço, o
  # código anexa os itens ao turno, e o Responder os entrega depois da fala dela; sem preço, o modelo recebe um
  # texto para falar, em todo estado. A ferramenta é síncrona e não publica nada sozinha (desenho da rodada 8).
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

    ExecucoesDaCotacao::NOMES.each do |desfalque|
      describe "com #{desfalque}" do
        it 'a primeira leitura com todas com desfecho pede a confirmacao logo, e o done seguinte dispara a conclusao' do
          register_async_tool(described_class)
          allow(mock).to receive(:quote_result)
            .and_return({ 'quote_id' => 'q-1:1', 'status' => 'partial', 'offers' => [offer('43', 'Ezze', 2050.40), recusa('3')] })
          run = cotacao_viva(desfalque)

          job.new.perform(run.id, 12)
          confirmacao = enqueued_jobs.find { |item| item[:job] == job && item[:args] == [run.id, 13] }
          job.new.perform(run.id, 13)

          expect(confirmacao[:at]).to be_within(2).of(3.seconds.from_now.to_f)
          expect(run.reload.status).to eq('done')
          expect(eventos_disparados(run)).to eq(['concluida'])
          expect(palavras_do_bot.compact).to be_empty
        end

        # A ferramenta da Lia lê a cotação cuja chamada teve este desfalque: o que ela devolve ao modelo são os dados
        # da cotação, e nunca uma frase do especialista ou uma constante. Quem fala é a Lia.
        it 'a ferramenta da Lia devolve ao modelo os dados de preco, sem frase pronta e sem publicar' do
          fonte = cotacao_viva(desfalque)
          fonte.record_attempt!(handle: { described_class::RESULTADO_KEY =>
                                            Autonomia::Insurance::ResultadoPorSeguradora.unir({}, [offer('43', 'Ezze', 2050.40)]) })
          fonte.finish!('done')
          delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 8)

          ao_modelo = resultado.new(agent: agent, params: { 'seguradora' => nil }, delivery: delivery).call

          expect(ao_modelo).to include('Ezze fez proposta: R$ 2.050,40 no total')
          expect(ExecucoesDaCotacao::FRASES_ANTIGAS.values.none? { |frase| ao_modelo.include?(frase) }).to be(true)
          expect(palavras_do_bot).to be_empty
        end
      end
    end

    # SEM PREÇO, QUEM FALA É A LIA, e ela recebe um texto em todo estado.
    it 'sem preco, o modelo recebe texto em todo estado da ferramenta da Lia' do
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 7)
      ao_modelo = ->(seguradora) { resultado.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: delivery).call }
      guardado = ->(ofertas) { { described_class::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) } }
      textos = [ao_modelo.call(nil)]

      run = cotacao_viva(ExecucoesDaCotacao::NOMES.first)
      textos << ao_modelo.call(nil)
      run.record_attempt!(handle: guardado.call([recusa('3')]))
      textos += [ao_modelo.call(nil), ao_modelo.call('Seguradora 3'), ao_modelo.call('Azul')]
      run.finish!('done')
      textos += [ao_modelo.call(nil), ao_modelo.call('Seguradora 3'), ao_modelo.call('Azul')]
      run.update!(handle: run.handle.except('quote_id'))
      textos << ao_modelo.call(nil)
      expect(textos.last).to eq(resultado::NAO_CHEGOU)
      run.update!(handle: run.handle.except(job::SUBMITTED_KEY).merge(Autonomia::Agents::ToolRun::INTENCOES => 1))
      textos << ao_modelo.call(nil)

      expect(textos.size).to eq(10)
      expect(textos).to all(be_present)
      expect(textos.last).to eq(resultado::ENVIO_INCERTO)
    end

    # SEM MOTOR: a ferramenta da Lia é síncrona, não abre execução, e nenhuma frase do motor sai por ela.
    it 'a ferramenta da Lia e sincrona e nao abre execucao' do
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 9)
      cotacao_viva(ExecucoesDaCotacao::NOMES.first)

      resultado.new(agent: agent, params: { 'seguradora' => nil }, delivery: delivery).call

      expect(resultado.async?).to be(false)
      expect(Autonomia::Agents::ToolRun.where(slug: resultado.slug)).to be_empty
      expect(palavras_do_bot).to be_empty
    end
  end

  # NENHUMA FRASE AO CLIENTE NO CONTRATO DA COTAÇÃO (PR C): nem as constantes de recuo, nem o nó das frases.
  describe 'o fim das frases prontas' do
    it 'a ferramenta nao responde por frase ao cliente, e o formulario nao pede frases ao especialista' do
      %i[waiting_message failure_message partial_message uncertain_message closing_message valores_message].each do |metodo|
        expect(described_class).not_to respond_to(metodo)
      end
      expect(described_class.params.pluck('name')).not_to include('frases_ao_cliente')
    end

    # 23/09/2026: o prazo com o comparativo entregue não é falha. Sem número, sem "refazer ou chamar a equipe".
    it 'o desfecho por prazo nao conta quantas seguradoras ficaram de fora, nem oferece refazer ou atendente' do
      texto = described_class.fatos_do_evento('encerrada_por_prazo', Autonomia::Agents::ToolRun.new(handle: {}))

      expect(texto).not_to match(/[0-9]/)
      expect(texto).to include('comparativo em PDF', 'instabilidade delas', 'não é motivo para refazer')
      expect(texto).not_to include('equipe')
    end

    def fatos(tipo, handle: {}, faixa: '')
      described_class.fatos_do_evento(tipo, Autonomia::Agents::ToolRun.new(handle: handle, faixa: faixa))
    end

    it 'falha e incerteza não prometem atendente: a passagem para uma pessoa não está ligada' do
      %w[falhou incerta].each do |tipo|
        expect(fatos(tipo)).to include('não prometa atendente')
        expect(fatos(tipo)).not_to include('vai continuar', 'vai conferir')
      end
    end

    # Revisão da chat#608: só a falha comum oferece pedir de novo. A incerta pode já ter cotado (e pago) no portal,
    # e o formulário indisponível recusaria de novo.
    it 'só a falha comum oferece pedir de novo' do
      expect(fatos('falhou')).to include('dá para pedir de novo')
      expect(fatos('incerta')).to include('não conseguiu confirmar', 'sem oferecer cotar de novo')
      expect(fatos('falhou', handle: { 'recusa' => 'formulario_indisponivel' })).to include('Não ofereça cotar de novo')
    end

    it 'os fatos dizem de qual seguro é a notícia' do
      expect(fatos('falhou', faixa: 'residencial')).to start_with('Cotação de residencial. ')
      expect(fatos('concluida')).to start_with('Cotação de auto. ')
    end
  end
end
