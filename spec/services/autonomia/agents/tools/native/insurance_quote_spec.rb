require 'rails_helper'

# A ferramenta que serve QUALQUER ramo — e o que estes exemplos travam é a promessa dela: nenhuma
# cotação é consumida por entrada incompleta, e o agente recebe o que perguntar em vez de um erro.
#
# A ferramenta de auto tem sete parâmetros digitados à mão em Ruby, e é só de auto. Esta não sabe
# nada sobre ramo nenhum: pergunta ao adapter o que falta e devolve a lista.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end

  before { enable_test_encryption! }

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com',
                                                      password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def tool(params)
    described_class.new(agent: agent, params: params)
  end

  def offer(code, name, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status }
    return base unless amount

    base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' })
  end

  it 'is asynchronous, like every quote that takes minutes' do
    expect(described_class.async?).to be(true)
  end

  # O ponto da ferramenta inteira. Cada cotação no AGGER consome consulta paga; a validação não
  # consome nada. Cotar antes de conferir seria gastar para descobrir o que já dava para saber.
  describe 'nao consome cotacao com entrada incompleta' do
    it 'devolve o que falta em vez de cotar' do
      # Arrange
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      expect(connector).not_to receive(:quote_start)

      # Act
      resultado = tool('produto' => 'bike', 'dados' => '{}').start

      # Assert
      expect(resultado['motivo']).to eq('faltam_dados')
      expect(resultado['pedido']).to include('valorMercado')
      expect(resultado['pedido']).to include('Nenhuma cotação foi consumida')
    end

    it 'cota quando a entrada esta completa' do
      # Arrange
      ready_connection
      dados = { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' }.to_json

      # Act
      resultado = tool('produto' => 'bike', 'dados' => dados).start

      # Assert
      expect(resultado['quote_id']).to be_present
      expect(resultado['produto']).to eq('bike')
    end

    # `aviso` fala de tabela possivelmente velha do NOSSO lado, e não de dado que falta ao cliente.
    # Perguntar por causa disso seria atrito sem causa — a cotação segue e o portal decide.
    it 'ignora aviso e so trava em erro' do
      # Arrange
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_validate).and_return(
        'valido' => true,
        'problemas' => [{ 'campo' => 'x', 'severidade' => 'aviso', 'motivo' => 'tabela velha' }]
      )

      # Act
      resultado = tool('produto' => 'bike', 'dados' => '{}').start

      # Assert
      expect(resultado['quote_id']).to be_present
    end
  end

  describe 'entrada que o modelo pode errar' do
    it 'pede o produto quando ele nao veio' do
      ready_connection
      resultado = tool('produto' => '', 'dados' => '{}').start

      expect(resultado['motivo']).to eq('produto_nao_informado')
      expect(resultado['pedido']).to include('qual seguro cotar')
    end

    # JSON quebrado não pode virar cotação vazia nem erro genérico: o agente precisa saber que o
    # formato estava errado para reenviar, em vez de repetir a pergunta ao cliente.
    it 'diz quando o JSON nao presta' do
      ready_connection
      resultado = tool('produto' => 'bike', 'dados' => '{marca: Caloi').start

      expect(resultado['motivo']).to eq('json_invalido')
    end

    it 'trata JSON que nao e objeto como invalido' do
      ready_connection
      expect(tool('produto' => 'bike', 'dados' => '[1,2]').start['motivo']).to eq('json_invalido')
    end

    it 'aceita dados vazios como primeira tentativa, e nao como erro' do
      ready_connection
      expect(tool('produto' => 'bike', 'dados' => '').start['motivo']).to eq('faltam_dados')
    end

    it 'recusa produto que o adapter nao conhece' do
      ready_connection
      expect { tool('produto' => 'drone', 'dados' => '{}').start }
        .to raise_error(Autonomia::Insurance::Connector::Error)
    end
  end

  # A recusa vira ENTREGA, e não falha. `failed` mandaria a mensagem genérica de erro e a conversa
  # morreria sem ninguém saber o que faltava.
  describe '#poll' do
    it 'entrega o pedido do que falta na primeira passada' do
      ready_connection
      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'pedido' => 'faltam X e Y' }, attempt: 1)

      expect(progresso.deliveries).to eq(['faltam X e Y'])
      expect(progresso.status).to eq(:done)
    end

    it 'falha sem id de cotacao' do
      ready_connection
      progresso = tool('produto' => 'bike', 'dados' => '{}').poll(handle: {}, attempt: 1)

      expect(progresso.status).to eq(:failed)
    end

    it 'entrega so quem cotou, do mais barato para o mais caro' do
      # Arrange
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_result).and_return(
        'status' => 'completed',
        'offers' => [offer('8', 'Porto', 'quoted', 900.0), offer('3', 'Mapfre', 'quoted', 700.0),
                     offer('9', 'Azul', 'declined'), offer('7', 'Pier', 'auth_required')]
      )

      # Act
      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'quote_id' => 'q1', 'entregues' => [] }, attempt: 1)

      # Assert — recusa de risco e problema de credencial nunca viram texto ao cliente.
      texto = progresso.deliveries.first
      expect(texto).to include('Mapfre')
      expect(texto).to include('Porto')
      expect(texto).not_to include('Azul')
      expect(texto).not_to include('Pier')
      expect(texto.index('Mapfre')).to be < texto.index('Porto')
    end

    # A segunda mensagem se anuncia como complemento; sem isso ela parece cotação nova e o cliente
    # não sabe qual vale.
    it 'nao repete quem ja foi entregue' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_result).and_return(
        'status' => 'running',
        'offers' => [offer('8', 'Porto', 'quoted', 900.0), offer('3', 'Mapfre', 'quoted', 700.0)]
      )

      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'quote_id' => 'q1', 'entregues' => ['3'] }, attempt: 1)

      expect(progresso.deliveries.first).to include('Chegaram mais opções')
      expect(progresso.deliveries.first).not_to include('Mapfre')
      expect(progresso.status).to eq(:running)
    end

    it 'nao entrega nada quando nenhum preco novo chegou' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_result).and_return('status' => 'running', 'offers' => [])

      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'quote_id' => 'q1', 'entregues' => [] }, attempt: 1)

      expect(progresso.deliveries).to eq([])
    end
  end

  describe 'contrato com o modelo' do
    # Duas ferramentas competindo pelo mesmo pedido fazem o modelo escolher por descrição. A desta é
    # necessariamente mais genérica, então ela precisa dizer por escrito que auto não é com ela.
    it 'manda o pedido de auto para a ferramenta especifica' do
      expect(described_class.description).to include('AUTOMÓVEL use a ferramenta específica')
    end

    it 'nomeia os ramos que atende, para o modelo saber quando usar' do
      %w[RESIDENCIAL VIAGEM VIDA CELULAR BICICLETA].each do |ramo|
        expect(described_class.description).to include(ramo)
      end
    end

    it 'esta no catalogo depois da de auto' do
      slugs = Autonomia::Agents::Tools::Registry.slugs
      expect(slugs).to include('cotar_seguro')
      expect(slugs.index('cotar_seguro')).to be > slugs.index('cotar_seguro_auto')
    end

    it 'so aparece para conta com conexao pronta' do
      expect(described_class.available_for?(agent)).to be(false)
      ready_connection
      expect(described_class.available_for?(agent)).to be(true)
    end
  end
end
