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
      # O `pedido` VAI PARA O CLIENTE (`Progress` chama deliveries de "textos destinados ao
      # cliente"). Esta linha exigia `configuracoes.valorMercado` no texto — o teste consagrando o
      # vazamento que levou `insured.document` a um WhatsApp em 08/09/2026. Campo de ramo não tem
      # rótulo que dê para escrever sem adivinhar, então a frase fica genérica e quem pergunta é o
      # modelo no turno seguinte.
      expect(resultado['pedido']).not_to include('configuracoes.valorMercado')
      expect(resultado['pedido']).not_to include('chame a ferramenta')
      expect(resultado['pedido']).to include('nome do titular')
    end

    # Campo que a própria ferramenta coleta tem rótulo, e o cliente lê o nome que ele reconhece.
    it 'pede o dado pelo nome que o cliente reconhece' do
      # Arrange
      ready_connection

      # Act
      resultado = tool('produto' => 'auto', 'placa' => 'ABC1D23').start

      # Assert
      expect(resultado['pedido']).to include('CPF do titular')
      expect(resultado['pedido']).not_to include('insured.document')
    end

    it 'cota quando a entrada esta completa' do
      # Arrange
      ready_connection
      dados = { segurado: { nome: 'Fulano', cpfCnpj: '04297912678' },
                configuracoes: { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' } }.to_json

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

  # O SEGURADO VEM DE DOIS LUGARES, e é onde um review adversarial achou o defeito: o JSON do
  # modelo vencia o parâmetro explícito INCLUSIVE quando vinha vazio, apagando o CPF que o cliente
  # já tinha dado. O portal recusaria uma cotação que tinha tudo.
  describe 'quem esta sendo segurado' do
    def entrada_montada(params)
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      capturada = nil
      allow(connector).to receive(:quote_validate) do |args|
        capturada = args[:input]
        { 'valido' => true, 'problemas' => [] }
      end
      tool(params).start
      capturada
    end

    it 'nao deixa o JSON vazio apagar o CPF que veio no parametro' do
      # Arrange
      ready_connection

      # Act
      entrada = entrada_montada('produto' => 'bike', 'cpf' => '042.979.126-78', 'nome' => 'Fulano',
                                'dados' => '{"segurado":{"cpfCnpj":"","nome":""}}')

      # Assert
      expect(entrada['segurado']['cpfCnpj']).to eq('04297912678')
      expect(entrada['segurado']['nome']).to eq('Fulano')
    end

    it 'deixa o JSON corrigir o parametro quando traz valor' do
      ready_connection
      entrada = entrada_montada('produto' => 'bike', 'cpf' => '042.979.126-78',
                                'dados' => '{"segurado":{"cpfCnpj":"11122233344"}}')

      expect(entrada['segurado']['cpfCnpj']).to eq('11122233344')
    end

    it 'limpa a pontuacao do CPF antes de mandar' do
      ready_connection
      entrada = entrada_montada('produto' => 'bike', 'cpf' => '042.979.126-78', 'dados' => '{}')

      expect(entrada['segurado']['cpfCnpj']).to eq('04297912678')
    end

    it 'nao inventa segurado quando ninguem informou' do
      ready_connection
      entrada = entrada_montada('produto' => 'bike', 'dados' => '{"marca":"Caloi"}')

      expect(entrada).not_to have_key('segurado')
    end

    # A comissão é da conexão, e não do modelo: um agente que a informasse mudaria o que a corretora
    # ganha por cotação.
    it 'manda a comissao da conexao, e nao a que o modelo escrever' do
      ready_connection
      entrada = entrada_montada('produto' => 'bike', 'dados' => '{"commissionPercent":99}')

      expect(entrada['commissionPercent']).to eq(described_class::DEFAULT_COMMISSION)
    end
  end

  describe 'entrada que o modelo pode errar' do
    # Sem produto, assume AUTO: é o ramo mais pedido, e era o único que a ferramenta anterior
    # atendia — o modelo que aprendeu a chamar sem dizer o produto continua acertando.
    it 'assume auto quando o produto nao veio' do
      ready_connection
      resultado = tool('produto' => '', 'cpf' => '04297912678', 'cep' => '31110210',
                       'placa' => 'TYV8I74').start

      expect(resultado['produto']).to eq('auto')
      expect(resultado['quote_id']).to be_present
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

    # `dados` é escrito por um modelo de linguagem: nem o formato nem o tamanho são garantidos. O
    # ramo que mais pede é a bike, com dezessete campos — muito abaixo do teto.
    it 'recusa sem parsear quando o JSON passa do teto' do
      ready_connection
      gigante = { lixo: 'x' * described_class::MAX_DADOS_BYTES }.to_json

      expect(tool('produto' => 'bike', 'dados' => gigante).start['motivo']).to eq('json_invalido')
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

  # O ÚNICO COMPORTAMENTO QUE É SÓ DE AUTO. Classe de bônus existe em apólice de carro; falar dela
  # numa cotação de bicicleta é o agente prometendo desconto que não existe naquele produto.
  describe 'o bonus de renovacao nao vaza para os outros ramos' do
    it 'nao marca renovacao sem bonus fora de auto' do
      # Arrange — os mesmos parâmetros que em auto disparariam o aviso.
      ready_connection
      dados = { configuracoes: { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' } }.to_json

      # Act
      resultado = tool('produto' => 'bike', 'dados' => dados, 'cpf' => '04297912678',
                       'nome' => 'Fulano', 'renovacao' => true).start

      # Assert
      expect(resultado[described_class::SEM_BONUS_KEY]).to be(false)
    end

    it 'marca em auto, que e onde a classe de bonus existe' do
      ready_connection
      resultado = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210',
                       'placa' => 'TYV8I74', 'renovacao' => true).start

      expect(resultado[described_class::SEM_BONUS_KEY]).to be(true)
    end
  end

  describe 'contrato com o modelo' do
    # HAVIA DUAS ferramentas, e a separação custava caro: o comparativo em PDF e o registro da
    # seguradora que recusou a credencial da corretora ficavam de fora dos outros dez ramos, e
    # nenhum dos dois é de auto. Uma só, e auto é um ramo com um comportamento extra.
    it 'cobre auto na mesma descricao dos outros ramos' do
      expect(described_class.description).to include('AUTOMÓVEL')
      expect(described_class.description).not_to include('ferramenta específica')
    end

    it 'nomeia os ramos que atende, para o modelo saber quando usar' do
      %w[RESIDENCIAL VIAGEM VIDA CELULAR BICICLETA].each do |ramo|
        expect(described_class.description).to include(ramo)
      end
    end

    # UMA ferramenta de cotação no catálogo. Duas competindo pelo mesmo pedido fariam o modelo
    # escolher por descrição, e a diferença entre elas não é do vocabulário do cliente.
    it 'e a unica ferramenta de cotacao do catalogo' do
      slugs = Autonomia::Agents::Tools::Registry.slugs
      expect(slugs).to include('cotar_seguro')
      expect(slugs.grep(/cotar/)).to eq(['cotar_seguro'])
    end

    it 'so aparece para conta com conexao pronta' do
      expect(described_class.available_for?(agent)).to be(false)
      ready_connection
      expect(described_class.available_for?(agent)).to be(true)
    end
  end
end
