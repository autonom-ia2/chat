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
