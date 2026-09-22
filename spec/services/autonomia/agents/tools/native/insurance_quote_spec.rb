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

  # Os fatos que o modelo lê no evento da recusa (PR C), a partir do handle que o `start` devolveu.
  def fatos(tipo, handle)
    described_class.fatos_do_evento(tipo, Autonomia::Agents::ToolRun.new(handle: handle))
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
      expect(resultado['recusa']).to eq('faltam_dados')
      # DESDE A PR C A RECUSA NÃO LEVA TEXTO AO CLIENTE: o handle traz o motivo e os problemas, e quem pergunta
      # é a Lia, a partir dos fatos do evento (para o MODELO: o nome do campo e o rótulo que o código conhece).
      expect(resultado).not_to have_key('pedido')
      expect(fatos('falta_dado', resultado)).to include('nome do titular')
    end

    # A CONFERÊNCIA DENTRO DO TURNO. É ela que faz a diferença entre pedir o CPF e anunciar uma
    # cotação que a validação recusa cinco segundos depois: o modelo espera o retorno da ferramenta
    # (`create_with_tool_executor` alimenta a segunda chamada com ele), então o texto chega a tempo.
    it 'devolve ao modelo o que falta, ainda no turno' do
      # Arrange
      ready_connection

      # Act
      conferencia = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }).precheck

      # Assert — o texto é o que o modelo lê; o motivo e os NOMES dos campos vão para o registro de
      # recusa (entrega 6), que precisa dizer QUAIS faltaram sem repetir o texto.
      # O modelo lê o CAMPO e o motivo do adapter (entrega 2): é assim que ele preenche certo na volta.
      expect(conferencia.to_s).to include('insured.document')
      expect(conferencia.motivo).to eq('faltam_dados')
      expect(conferencia.faltando).to include('insured.document')
      expect(conferencia.faltando).to all(match(/\A[a-z]+\.[a-zA-Z]+\z/))
    end

    it 'nao interrompe quando a entrada esta completa' do
      ready_connection

      texto = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => '04297912678',
                   'cep' => '31110-210').precheck

      expect(texto).to be_nil
    end

    # O VALOR RECUSADO VAI PARA O REGISTRO (#585): só o das coberturas, e o do documento nunca.
    it 'entrega ao registro o valor das coberturas recusadas, e só delas' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      problemas = [{ 'campo' => 'coverage.assistance24h', 'severidade' => 'erro', 'motivo' => '2000 não existe' },
                   { 'campo' => 'insured.document', 'severidade' => 'erro', 'motivo' => 'CPF inválido' }]
      allow(connector).to receive(:quote_validate).and_return('valido' => false, 'problemas' => problemas)

      conferencia = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => '04297912678',
                         'coverage' => { 'assistance24h' => 2000 }).precheck

      expect(conferencia.recusados).to eq('coverage.assistance24h' => 2000)
    end

    # Um caminho de campo que desce além de um valor não pode levantar: a exceção cairia no `rescue` do
    # `precheck`, e a conferência aceitaria a cotação paga com o valor inválido (revisão da #586).
    it 'recusa mesmo quando o campo recusado desce além de um valor, sem levantar' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      problemas = [{ 'campo' => 'coverage.assistance24h.nivel', 'severidade' => 'erro', 'motivo' => 'fora da lista' }]
      allow(connector).to receive(:quote_validate).and_return('valido' => false, 'problemas' => problemas)

      conferencia = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => '04297912678',
                         'coverage' => { 'assistance24h' => 1 }).precheck

      expect(conferencia.motivo).to eq('faltam_dados')
      expect(conferencia.recusados).to eq('coverage.assistance24h.nivel' => nil)
    end

    # Conferência é conferência, não portão: se ela cair, a cotação segue.
    it 'deixa passar quando a conferencia cai' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_validate).and_raise(StandardError)

      expect(tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }).precheck).to be_nil
    end

    # Campo que a própria ferramenta coleta tem rótulo, e o cliente lê o nome que ele reconhece.
    it 'pede o dado pelo nome que o cliente reconhece' do
      # Arrange
      ready_connection

      # Act
      resultado = tool('produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }).start

      # Assert — e o handle leva os NOMES dos campos para o job registrar a recusa (entrega 6)
      expect(fatos('falta_dado', resultado)).to include('insured.document (CPF do titular)')
      expect(resultado).not_to have_key('pedido')
      expect(resultado['faltando']).to include('insured.document')
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
                       'vehicle' => { 'plate' => 'TYV8I74' }).start

      expect(resultado['produto']).to eq('auto')
      expect(resultado['quote_id']).to be_present
    end

    # JSON quebrado não pode virar cotação vazia nem erro genérico: o agente precisa saber que o
    # formato estava errado para reenviar, em vez de repetir a pergunta ao cliente.
    it 'diz quando o JSON nao presta' do
      ready_connection
      resultado = tool('produto' => 'bike', 'dados' => '{marca: Caloi').start

      expect(resultado['recusa']).to eq('json_invalido')
    end

    it 'trata JSON que nao e objeto como invalido' do
      ready_connection
      expect(tool('produto' => 'bike', 'dados' => '[1,2]').start['recusa']).to eq('json_invalido')
    end

    it 'aceita dados vazios como primeira tentativa, e nao como erro' do
      ready_connection
      expect(tool('produto' => 'bike', 'dados' => '').start['recusa']).to eq('faltam_dados')
    end

    # `dados` é escrito por um modelo de linguagem: nem o formato nem o tamanho são garantidos. O
    # ramo que mais pede é a bike, com dezessete campos — muito abaixo do teto.
    it 'recusa sem parsear quando o JSON passa do teto' do
      ready_connection
      gigante = { lixo: 'x' * described_class::MAX_DADOS_BYTES }.to_json

      expect(tool('produto' => 'bike', 'dados' => gigante).start['recusa']).to eq('json_invalido')
    end

    # Antes levantava, o job tentava 60 vezes por 7 minutos e o cliente esperava tudo isso por um
    # "não consegui" genérico. Ramo desconhecido é recusa nomeada, no envio e na conferência.
    it 'recusa produto que o adapter nao conhece, sem levantar e sem abrir cotacao' do
      ready_connection

      resultado = tool('produto' => 'drone', 'dados' => '{}').start

      expect(resultado['recusa']).to eq('ramo_desconhecido')
      expect(resultado['faltando']).to eq(['produto'])
      expect(fatos('ramo_desconhecido', resultado)).to include('automóvel')
      expect(tool('produto' => 'drone', 'dados' => '{}').precheck.motivo).to eq('ramo_desconhecido')
    end
  end

  # A FRONTEIRA DA CHAMADA PAGA (entrega 5). O que falha DEPOIS de `quote_start` sair sem o portal
  # dizer "não fiz" é `EnvioIncerto`: o job mantém a intenção e repete no máximo uma vez, marcada.
  # O que falha antes, ou com o portal dizendo que recusou, sobe como está: a intenção volta atrás.
  # Em 10/09/2026 um timeout do connector depois de o portal criar a cotação era lido como "não fez".
  describe 'a fronteira da chamada paga' do
    let(:incerto) { Autonomia::Agents::Tools::Native::EnvioIncerto }
    let(:erro) { Autonomia::Insurance::Connector::Error }
    let(:dados) do
      { segurado: { nome: 'Fulano', cpfCnpj: '04297912678' },
        configuracoes: { marca: 'Caloi', valorMercado: 8000, numeroSerie: 'SN-1' } }.to_json
    end

    def connector_dublado
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      connector
    end

    def cotar
      tool('produto' => 'bike', 'dados' => dados).start
    end

    it 'timeout, indisponivel e resposta ilegivel sao envio incerto, com o motivo e a causa' do
      ready_connection
      connector = connector_dublado

      %i[timeout unavailable protocol].each do |kind|
        allow(connector).to receive(:quote_start).and_raise(erro.new(kind, 'texto do portal'))

        expect { cotar }.to raise_error(incerto) do |e|
          expect(e.motivo).to eq(kind.to_s)
          expect(e.cause).to be_a(erro)
          expect(e.message).not_to include('texto do portal')
        end
      end
    end

    it 'erro que nao e do connector, depois da chamada sair, tambem e envio incerto' do
      ready_connection
      allow(connector_dublado).to receive(:quote_start).and_raise(NoMethodError, 'undefined method')

      expect { cotar }.to raise_error(incerto) { |e| expect(e.motivo).to eq('NoMethodError') }
    end

    it 'resposta sem id de cotacao e envio incerto: o portal respondeu, e nao se sabe o que fez' do
      ready_connection
      allow(connector_dublado).to receive(:quote_start).and_return({ 'status' => 'ok' })

      expect { cotar }.to raise_error(incerto) { |e| expect(e.motivo).to eq('resposta sem quote_id') }
    end

    it 'o portal recusando a credencial sobe como esta: nao cotou' do
      ready_connection
      connector = connector_dublado

      # `auth_required` renova a sessão e chama de novo; recusada duas vezes, sobe como está
      allow(connector).to receive(:quote_start).and_raise(erro.new(:auth_required, '401'))
      expect { cotar }.to raise_error(erro) { |e| expect(e.kind).to eq(:auth_required) }
      expect(connector).to have_received(:quote_start).twice
    end

    # #470. O adapter confere a entrada ANTES do `calcularV2`: nada foi cotado. Sem a pessoa na
    # consulta de CPF faltam nascimento e sexo, e isso é pergunta ao cliente, não falha passageira.
    # Antes subia como erro, e o job tentava 15 vezes até o prazo.
    it 'entrada recusada pelo adapter vira a recusa faltam_dados, com o pedido e o que faltou' do
      ready_connection
      connector = connector_dublado
      issues = ['insured.birthDate: Required', 'insured.gender: Required']
      allow(connector).to receive(:quote_start).and_raise(erro.new(:validation, 'auto quote input invalid', { 'issues' => issues }))

      resultado = cotar

      expect(resultado['recusa']).to eq('faltam_dados')
      expect(resultado['faltando']).to eq(%w[insured.birthDate insured.gender])
      expect(resultado['problemas']).to eq([{ 'campo' => 'insured.birthDate', 'motivo' => 'Required' },
                                            { 'campo' => 'insured.gender', 'motivo' => 'Required' }])
      expect(fatos('falta_dado', resultado)).to include('data de nascimento do titular', 'sexo do titular')
      expect(resultado).not_to have_key('quote_id')
      expect(connector).to have_received(:quote_start).once
    end

    # Sem `details.issues` é o portal recusando o `calcularV2`, ou a corretora sem seguradora no
    # ramo: não é pergunta ao cliente, e segue subindo como antes.
    it 'validation sem a lista de campos sobe como esta: nao vira pedido ao cliente' do
      ready_connection
      allow(connector_dublado).to receive(:quote_start)
        .and_raise(erro.new(:validation, 'nenhuma seguradora habilitada neste ramo', { 'ramo' => '2' }))

      expect { cotar }.to raise_error(erro) { |e| expect(e.kind).to eq(:validation) }
    end

    # Erro de FORMATO pediria de novo um dado que o cliente já deu: só campo AUSENTE vira pergunta.
    it 'validation so de formato nao vira pedido ao cliente: sobe como esta' do
      ready_connection
      allow(connector_dublado).to receive(:quote_start)
        .and_raise(erro.new(:validation, 'auto quote input invalid', { 'issues' => ['vehicle.plate: placa com 7 caracteres'] }))

      expect { cotar }.to raise_error(erro) { |e| expect(e.kind).to eq(:validation) }
    end

    it 'com ausente e formato juntos, pede so o ausente' do
      ready_connection
      issues = ['insured.birthDate: Required', 'vehicle.plate: placa com 7 caracteres']
      allow(connector_dublado).to receive(:quote_start).and_raise(erro.new(:validation, 'x', { 'issues' => issues }))

      expect(cotar['faltando']).to eq(%w[insured.birthDate])
    end

    it 'validation fora do quote_start (no login) nao vira pedido ao cliente: sobe como esta' do
      record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      record.update!(status: 'ready')
      connector = connector_dublado
      allow(connector).to receive(:open_session).and_raise(erro.new(:validation, 'credenciais'))

      expect { cotar }.to raise_error(erro) { |e| expect(e.kind).to eq(:validation) }
    end

    it 'falha ANTES da chamada paga (o login) sobe como esta, e o portal nao e chamado' do
      # Arrange — conexão pronta sem sessão viva: o login roda antes do `quote_start`, e cai
      record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      record.update!(status: 'ready')
      connector = connector_dublado
      allow(connector).to receive(:open_session).and_raise(erro.new(:unavailable, 'login caiu'))
      allow(connector).to receive(:quote_start).and_call_original

      # Act / Assert
      expect { cotar }.to raise_error(erro) { |e| expect(e.kind).to eq(:unavailable) }
      expect(connector).not_to have_received(:quote_start)
    end
  end

  # A recusa vira EVENTO (PR C), e não falha. `failed` mandaria o evento genérico de falha e a conversa
  # morreria sem ninguém saber o que faltava.
  describe '#poll' do
    it 'devolve a recusa como done com o evento, sem entrega' do
      ready_connection
      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'recusa' => 'faltam_dados', 'faltando' => ['x'] }, attempt: 1)

      expect(progresso.deliveries).to be_empty
      expect(progresso.evento).to eq('falta_dado')
      expect(progresso.status).to eq(:done)
    end

    # A EXECUÇÃO QUE ATRAVESSOU O DEPLOY traz o texto velho em `pedido`: ele não é reaproveitado.
    it 'a recusa de uma execucao anterior a PR C vira o mesmo evento, sem o texto antigo' do
      ready_connection
      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'pedido' => 'faltam X e Y', 'motivo' => 'sem_veiculo', 'faltando' => ['vehicle.plate'] }, attempt: 1)

      expect(progresso.deliveries).to be_empty
      expect(progresso.evento).to eq('falta_dado')
    end

    it 'o motivo de cada recusa vira o seu evento' do
      ready_connection
      evento = ->(motivo) { tool('produto' => 'bike', 'dados' => '{}').poll(handle: { 'recusa' => motivo }, attempt: 1).evento }

      expect(%w[faltam_dados json_invalido sem_veiculo ramo_desconhecido formulario_indisponivel outro].map(&evento))
        .to eq(%w[falta_dado falta_dado falta_dado ramo_desconhecido falhou falhou])
    end

    it 'falha sem id de cotacao' do
      ready_connection
      progresso = tool('produto' => 'bike', 'dados' => '{}').poll(handle: {}, attempt: 1)

      expect(progresso.status).to eq(:failed)
    end

    # A CONSULTA GRAVA E NÃO PUBLICA (fatia 3 do #420): o preço que chegou não vira lista ao cliente. Fica
    # gravado quem cotou (união com o que já estava) e o resultado por seguradora, que a Lia lê quando o
    # cliente pergunta. Recusa de risco e credencial também não viram texto.
    it 'grava quem cotou e o resultado, e nao publica lista de preco' do
      ready_connection
      connector = Autonomia::Insurance::Connector.client
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      allow(connector).to receive(:quote_result).and_return(
        'status' => 'running',
        'offers' => [offer('8', 'Porto', 'quoted', 900.0), offer('3', 'Mapfre', 'quoted', 700.0),
                     offer('9', 'Azul', 'declined'), offer('7', 'Pier', 'auth_required')]
      )

      progresso = tool('produto' => 'bike', 'dados' => '{}')
                  .poll(handle: { 'quote_id' => 'q1', 'entregues' => ['5'] }, attempt: 1)

      expect(progresso.status).to eq(:running)
      expect(progresso.deliveries).to eq([])
      expect(progresso.handle['entregues']).to contain_exactly('5', '3', '8')
      expect(progresso.handle[described_class::RESULTADO_KEY].keys).to contain_exactly('8', '3', '9', '7')
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
                       'nome' => 'Fulano', 'quotation' => { 'isRenewal' => true }).start

      # Assert
      expect(resultado[described_class::SEM_BONUS_KEY]).to be(false)
    end

    it 'marca em auto, que e onde a classe de bonus existe' do
      ready_connection
      resultado = tool('produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210',
                       'vehicle' => { 'plate' => 'TYV8I74' }, 'quotation' => { 'isRenewal' => true }).start

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
