require 'rails_helper'

# A FERRAMENTA DA LIA QUE VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420) E DEVOLVE OS PREÇOS A ELA (fatia 3): síncrona,
# sobre linhas reais de `autonomia_agent_tool_runs`. O que o modelo lê é o texto que `call` devolve, e o mesmo texto
# fica registrado no turno (`Tools::Delivery#resultado_do_turno`) para a conferência da fala. O caminho pelo turno e
# pelo Responder está em `answerer_resultado_da_cotacao_spec`. Dados sintéticos.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuoteResult do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 90) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:guardar) { Autonomia::Insurance::ResultadoPorSeguradora }
  let(:risco) { { 'kind' => 'risco', 'text' => 'Tipo de veículo não aceito.' } }
  let(:porto) { cotou('8', 'Porto Seguro', 2119.18) }
  let(:allianz) { cotou('5', 'Allianz', 2402.55) }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def cotou(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total',
                     'installments' => { 'count' => 10, 'amount' => (amount / 10).round(2) } } }
  end

  def recusou(code, name, status: 'declined', reason: nil)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status, 'reason' => reason }.compact
  end

  def correndo(code, name)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'running' }
  end

  def ofertas_padrao
    [porto, allianz, recusou('19', 'Sancor', reason: risco), recusou('13', 'Mitsui', status: 'auth_required', reason: risco)]
  end

  # Uma execução de `cotar_seguro` da conversa, com o resultado guardado destas ofertas (ou sem a chave).
  def cotacao_com(status:, ofertas: ofertas_padrao, guardado: true, handle: {}, criada: Time.current)
    base = { 'quote_id' => 'q-1:1' }
    base[cotacao::RESULTADO_KEY] = guardar.unir({}, ofertas) if guardado
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: status,
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                       arguments: {}, handle: base.merge(handle), created_at: criada)
  end

  # -> o que o modelo lê nesta chamada, no turno de `turno` (a `delivery` do exemplo, por padrão).
  def ao_modelo(seguradora = nil, turno: delivery)
    described_class.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: turno).call
  end

  # A linha que o modelo lê de uma seguradora com preço.
  def preco(oferta)
    premio = Autonomia::Insurance::PremiumText.new(oferta['premium'])
    "#{oferta.dig('insurer', 'name')} fez proposta: #{[premio.resumo, premio.detalhe].compact.join(', ')}."
  end

  it 'é síncrona e não abre execução' do
    cotacao_com(status: 'done')

    ao_modelo

    expect(described_class.async?).to be(false)
    expect(Autonomia::Agents::ToolRun.where(slug: described_class.slug)).to be_empty
  end

  # SEM CONTEXTO DE ENTREGA (Testar, Copiloto, playground): erro nomeado, pelo registro de recusa.
  it 'sem contexto de entrega, devolve o erro nomeado e não lê cotação nenhuma' do
    cotacao_com(status: 'done')

    saida = described_class.new(agent: agent, params: { 'seguradora' => nil }).call

    expect(JSON.parse(saida)).to eq('error' => described_class::SEM_CONTEXTO)
  end

  describe 'o que chega ao modelo, sem preço' do
    # Nesses estados o modelo não recebe valor nenhum, e o que fica registrado no turno é o mesmo texto.
    def ao_modelo(seguradora = nil, turno: delivery)
      super.tap do |texto|
        expect(Autonomia::Agents::ConferenciaDePrecos.valores(texto)).to be_empty
        # O turno ACUMULA as leituras, e o resumo da entrada não entra na conferência (PR #518): o que
        # fica registrado termina com a parte dos PREÇOS desta leitura.
        expect(turno.resultado_do_turno.texto).to end_with(texto.split("\nCom que dados esta cotação foi pedida").first)
      end
    end

    it 'sem cotação na conversa' do
      expect(ao_modelo).to eq(described_class::SEM_COTACAO)
    end

    it 'cotação encerrada antes desta versão, sem o resultado guardado' do
      cotacao_com(status: 'done', guardado: false)

      expect(ao_modelo).to eq(described_class::SEM_RESULTADO)
    end

    # A MAIS NOVA É UMA RECUSA DO `start` (faltou dado): ela nunca teve número no portal, e esconde a anterior
    # com preço. O modelo ouve que ela não chegou às seguradoras.
    it 'a cotação mais nova encerrada sem número do portal não chegou às seguradoras' do
      cotacao_com(status: 'done', criada: 10.minutes.ago)
      cotacao_com(status: 'done', guardado: false, criada: 1.minute.ago,
                  handle: { 'quote_id' => nil, 'pedido' => 'Qual o ano do veículo?', 'motivo' => 'faltam_dados' })

      expect(ao_modelo).to eq(described_class::NAO_CHEGOU)
      expect(ao_modelo('Porto')).to eq(described_class::NAO_CHEGOU)
    end

    it 'a cotação correndo que ainda não recebeu número do portal está ainda sem preço' do
      cotacao_com(status: 'running', guardado: false, handle: { 'quote_id' => nil })

      expect(ao_modelo).to eq(described_class::SEM_PRECO_AINDA)
    end

    # ENVIO INCERTO: o job decidiu submeter e o número nunca chegou. O cliente ouviu que um atendente vai conferir.
    it 'a cotação encerrada com envio incerto: pode ter chegado às seguradoras, e um atendente vai conferir' do
      incerta = { 'quote_id' => nil, Autonomia::Agents::ToolRun::INTENCOES => 1 }
      run = cotacao_com(status: 'failed', guardado: false, handle: incerta)
      expect(ao_modelo).to eq(described_class::ENVIO_INCERTO)
      expect(ao_modelo('Porto')).to eq(described_class::ENVIO_INCERTO)

      run.update!(status: 'running')
      expect(ao_modelo).to eq(described_class::SEM_PRECO_AINDA)
    end

    it 'cotação em voo no deploy, correndo e ainda sem o resultado guardado' do
      cotacao_com(status: 'running', guardado: false)

      expect(ao_modelo).to eq(described_class::SEM_PRECO_AINDA)
    end

    it 'só recusas: ainda correndo, e depois de encerrada' do
      run = cotacao_com(status: 'running', ofertas: [recusou('19', 'Sancor', reason: risco)])
      expect(ao_modelo).to eq(described_class::SEM_PRECO_AINDA)

      run.update!(status: 'done')
      expect(ao_modelo).to eq(described_class::SEM_PRECO)
    end

    it 'seguradora sem proposta, com o motivo do veículo: quantas cotaram, o nome e a categoria' do
      cotacao_com(status: 'done')

      texto = ao_modelo('Sancor')

      expect(texto.split("\n")).to eq(['2 seguradoras fizeram proposta nesta cotação.',
                                       "Sancor não fez proposta nesta cotação. #{described_class::MOTIVOS.fetch('veiculo')}"])
      expect(texto).to include('Categoria do motivo: veiculo.')
      expect(texto).not_to include(risco['text'])
    end

    it 'seguradora recusada pela região: a categoria da região' do
      cotacao_com(status: 'done', ofertas: [recusou('19', 'Sancor', reason: { 'kind' => 'risco', 'text' => 'CEP sem aceitação.' })])

      expect(ao_modelo('Sancor')).to include("Sancor não fez proposta nesta cotação. #{described_class::MOTIVOS.fetch('regiao')}")
    end

    # NENHUM TEXTO DO PORTAL CHEGA AO MODELO: o corpus do conector, no kind e no status que ele dá, os textos das
    # revisões e as sondas da revisão da sétima rodada. O modelo lê uma de três falas fechadas; conta e pessoa, a genérica.
    it 'o modelo nunca recebe texto do portal, em nenhuma mensagem do corpus, das revisões nem das sondas' do
      genericos = TextosDoMotivo::CONTA + TextosDoMotivo::PESSOA + TextosDoMotivo::REVISOES + SondasDoMotivo::REVISAO_7
      linhas = TextosDoMotivo::CORPUS.map { |linha| linha.first(3) } + genericos.map { |texto| [texto, 'risco', 'declined'] }
      cotacao_com(status: 'done', ofertas: linhas.each_with_index.map do |(texto, kind, status), i|
        recusou(i.to_s, "Seguradora #{i}", status: status, reason: { 'kind' => kind, 'text' => texto })
      end)

      falas = linhas.each_index.map do |i|
        ao_modelo("Seguradora #{i}").split("\n").last.delete_prefix("Seguradora #{i} não fez proposta nesta cotação. ")
      end

      expect(falas.uniq - [described_class::SEM_MOTIVO, *described_class::MOTIVOS.values]).to be_empty
      expect(linhas.each_with_index.select { |(texto, _, _), i| falas[i].include?(texto) }).to be_empty
      expect(falas.last(genericos.size)).to all(eq(described_class::SEM_MOTIVO))
    end

    it 'seguradora que recusou a credencial: não fez proposta, sem motivo e sem palavra de conta' do
      cotacao_com(status: 'done')

      texto = ao_modelo('Mitsui')

      expect(texto).to include("Mitsui não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
      expect(texto.downcase).not_to match(/login|senha|permiss|credencia|acesso|corretor/)
    end

    # A LEITURA SÓ ACEITA AS CATEGORIAS: um motivo guardado em outra forma não chega ao modelo.
    it 'motivo guardado fora das categorias não chega ao modelo' do
      ['conta', { 'kind' => 'risco', 'text' => 'Senha expirou. Declinando cálculo.' }].each do |guardado|
        entrada = { 'nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => guardado }
        Autonomia::Agents::ToolRun.where(slug: cotacao.slug).delete_all
        cotacao_com(status: 'done', guardado: false, handle: { cotacao::RESULTADO_KEY => { '19' => entrada } })

        expect(Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation.id).motivo('19')).to be_nil
        expect(ao_modelo('sancor')).to include("Sancor não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
      end
    end

    it 'seguradora ainda sem desfecho: ainda não respondeu enquanto corre; não fez proposta depois de encerrada' do
      run = cotacao_com(status: 'running', ofertas: [correndo('47', 'Justos'), recusou('19', 'Sancor')])
      expect(ao_modelo('Justos')).to include('Justos ainda não respondeu, e a cotação continua correndo.')

      run.update!(status: 'failed')
      expect(ao_modelo('Justos')).to include("Justos não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
    end

    it 'o portal já fechou: quem ficou sem desfecho não fez proposta, mesmo com a execução viva' do
      cotacao_com(status: 'running', ofertas: [correndo('47', 'Justos')], handle: { cotacao::FECHADO_KEY => true })

      expect(ao_modelo('Justos')).to include('Justos não fez proposta')
    end

    it 'nome que não está na cotação: encerrada, e ainda correndo' do
      run = cotacao_com(status: 'done')
      expect(ao_modelo('Azul')).to eq(described_class::NAO_ENCONTRADA)

      run.update!(status: 'running')
      expect(ao_modelo('Azul')).to eq(described_class::NAO_ENCONTRADA_AINDA)
    end
  end

  describe 'com preço' do
    # O RECORTE É DA LIA (fatia 3 do #420): a ferramenta devolve todas, com o valor, o período e o parcelamento, e
    # a regra de como escrever. Na prova real de 18/09/2026 o cliente pediu só as três mais baratas e recebeu onze.
    it 'o resultado inteiro: quantas cotaram, cada preço com o período, quem não fez proposta, e como escrever' do
      cotacao_com(status: 'running')

      texto = ao_modelo

      expect(texto.split("\n")).to eq(['2 seguradoras fizeram proposta até agora.', preco(porto), preco(allianz),
                                       described_class::HA_SEM_PROPOSTA, 'Mitsui não fez proposta nesta cotação.',
                                       'Sancor não fez proposta nesta cotação.', described_class::AINDA_CORRENDO,
                                       described_class::COMO_ESCREVER])
      expect(texto).to include('Porto Seguro fez proposta: R$ 2.119,18 no total, ou 10x de R$ 211,92.')
      expect(texto).not_to include(described_class::MOTIVOS.fetch('veiculo'))
    end

    it 'a mensal diz por mês, sem parcelamento, e vem depois dos totais' do
      mensal = { 'insurer' => { 'code' => '55', 'name' => 'Bp Assinatura' }, 'status' => 'quoted',
                 'premium' => { 'amount' => 199.9, 'currency' => 'BRL', 'basis' => 'monthly' } }
      cotacao_com(status: 'done', ofertas: [mensal, porto])

      linhas = ao_modelo.split("\n")

      expect(linhas[1..2]).to eq([preco(porto), 'Bp Assinatura fez proposta: R$ 199,90 por mês.'])
    end

    it 'cotação encerrada sem bônus, com o comparativo entregue' do
      run = cotacao_com(status: 'done', ofertas: [porto], handle: { cotacao::SEM_BONUS_KEY => true,
                                                                    cotacao::COMPARATIVO_KEY => 'tok-pdf' })
      run.registrar_entrega_aceita!('tok-pdf')

      expect(ao_modelo.split("\n")).to eq(['1 seguradora fez proposta nesta cotação.', preco(porto), described_class::SEM_BONUS,
                                           described_class::COMPARATIVO_ENVIADO, described_class::COMO_ESCREVER])
      expect(delivery.resultado_do_turno.comparativo).to be(true)
    end

    it 'uma seguradora com preço: só ela' do
      cotacao_com(status: 'done')

      texto = ao_modelo('a porto')

      expect(texto).to include(preco(porto), described_class::COMO_ESCREVER)
      expect(texto).not_to include('Allianz')
    end

    it 'uma com preço e uma sem proposta no mesmo pedido: o preço de uma e a categoria da outra' do
      cotacao_com(status: 'done')

      texto = ao_modelo('Sancor e Porto')

      expect(texto).to include(preco(porto), 'Sancor não fez proposta nesta cotação.', described_class::MOTIVOS.fetch('veiculo'))
      expect(texto).not_to include(risco['text'])
    end

    # O QUE A CONFERÊNCIA RECEBE: só a parte dos PREÇOS do texto que o modelo leu, todas as seguradoras da
    # cotação e se o PDF já foi. O resumo da entrada fica de fora de propósito (revisão da PR #518): ele cita a
    # seguradora ANTERIOR da renovação, e tê-la nos dados autorizaria a Lia a afirmar o desfecho dela.
    it 'registra no turno o texto, as seguradoras da cotação e o comparativo' do
      cotacao_com(status: 'done')

      texto = ao_modelo('Porto')

      expect(delivery.resultado_do_turno.texto).to eq(texto)
      expect(delivery.resultado_do_turno.seguradoras).to contain_exactly('Porto Seguro', 'Allianz', 'Sancor', 'Mitsui')
      expect(delivery.resultado_do_turno.comparativo).to be(false)
    end
  end

  # O MODELO NUNCA RECEBE TEXTO DO PORTAL NEM TRAVESSÃO, em nenhum estado.
  it 'nenhum texto ao modelo tem travessão, em nenhum estado' do
    cotacao_com(status: 'running', handle: { cotacao::SEM_BONUS_KEY => true })
    textos = [nil, 'Porto', 'Allianz', 'Sancor', 'Mitsui', 'Sancor e Porto', 'Azul'].map do |seguradora|
      ao_modelo(seguradora, turno: Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil))
    end

    expect(textos).to all(be_present)
    expect(textos.join("\n")).not_to match(/—|–/)
    expect(textos.join("\n")).not_to include(risco['text'])
  end

  describe 'mais de uma chamada' do
    it 'duas chamadas no mesmo turno somam no que fica registrado para a conferência' do
      cotacao_com(status: 'done')

      ao_modelo('Allianz')
      ao_modelo('Porto')

      expect(Autonomia::Agents::ConferenciaDePrecos.valores(delivery.resultado_do_turno.texto)).to include(211_918, 240_255)
    end
  end

  describe 'qual cotação ela lê, no instante da pergunta' do
    Autonomia::Insurance::ResultadoDaCotacao::FORA.each do |status|
      it "a mais nova que não está #{status}" do
        cotacao_com(status: 'done', ofertas: [porto], criada: 10.minutes.ago)
        cotacao_com(status: status, ofertas: [allianz], criada: 1.minute.ago)

        expect(ao_modelo).to include(preco(porto))
        expect(ao_modelo).not_to include('Allianz')
      end
    end

    it 'a mais nova encerrada sem preço vence a anterior com preço' do
      cotacao_com(status: 'done', ofertas: [porto], criada: 10.minutes.ago)
      cotacao_com(status: 'failed', ofertas: [recusou('19', 'Sancor')], criada: 1.minute.ago)

      expect(ao_modelo).to eq(described_class::SEM_PRECO)
    end

    it 'a cotação trocada entre duas perguntas: a segunda lê a nova' do
      cotacao_com(status: 'done', ofertas: [porto], criada: 10.minutes.ago)
      primeiro = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil)
      ao_modelo(nil, turno: primeiro)

      cotacao_com(status: 'running', ofertas: [allianz], criada: 1.second.from_now)
      ao_modelo

      expect(primeiro.resultado_do_turno.texto).to include(preco(porto))
      expect(delivery.resultado_do_turno.texto).to include(preco(allianz))
      expect(delivery.resultado_do_turno.texto).not_to include('Porto')
    end

    it 'não lê cotação de outra conversa' do
      outra = create(:conversation, account: account, inbox: inbox)
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: 'done',
                                         conversation_id: outra.id, execution_key: SecureRandom.uuid, arguments: {},
                                         handle: { 'quote_id' => 'q-1:1', cotacao::RESULTADO_KEY => guardar.unir({}, ofertas_padrao) })

      expect(ao_modelo).to eq(described_class::SEM_COTACAO)
    end
  end

  describe 'a procura pelo nome que o cliente escreveu' do
    # '99' veio sem nome do portal: sem palavra no nome, ela não pode casar com consulta nenhuma.
    let(:nomes) do
      { '8' => 'Porto Seguro', '19' => 'Sancor', '48' => 'Bp', '55' => 'Bp Assinatura', '12' => 'Liberty Site',
        '11' => 'Tokio', '4' => 'Hdi', '99' => '' }
    end

    before { cotacao_com(status: 'done', ofertas: nomes.map { |code, name| recusou(code, name) }) }

    {
      'porto' => %w[8], 'Porto Seguro' => %w[8], 'Sancor Seguros' => %w[19], 'HDI' => %w[4], 'bp' => %w[48],
      'Bp Assinatura' => %w[55], 'a assinatura' => %w[55], 'liberty' => %w[12], 'Liberty e Porto' => %w[8 12],
      'Tokio Marine' => %w[11], 'Bp e Sancor' => %w[19 48], 'azul' => [], 'seguradora' => [], '' => []
    }.each do |consulta, codigos|
      it "«#{consulta}» nomeia #{codigos.inspect}" do
        resultado = Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation.id)

        expect(resultado.procurar(consulta)).to match_array(codigos)
      end
    end
  end

  # COM QUE DADOS A COTAÇÃO FOI FEITA (#515). Em 19/09/2026 o cliente perguntou "o bônus da apólice foi
  # considerado?" e a Lia escalou: a ferramenta devolvia desfechos e nenhuma palavra sobre a entrada.
  describe 'o resumo da entrada da cotação' do
    let(:renovacao) do
      { 'produto' => 'auto', 'cep' => '01310-930', 'vehicle' => { 'plate' => 'ABC1D23' },
        'quotation' => { 'isRenewal' => true, 'bonusClass' => 9, 'previousClaimsCount' => 1,
                         'previousInsurerCode' => '657' } }
    end

    def conexao_com_schema
      enable_test_encryption!
      registro = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
      registro.update!(status: 'ready')
      registro.merge_metadata!('quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO })
    end

    def cotacao_pedida_com(argumentos, status: 'done')
      run = cotacao_com(status: status)
      run.update!(arguments: argumentos)
      run
    end

    it 'a renovação chega ao modelo com bônus, seguradora anterior e sinistros' do
      conexao_com_schema
      cotacao_pedida_com(renovacao)

      texto = ao_modelo

      expect(texto).to include('Tipo de seguro: renovação de apólice anterior.')
      expect(texto).to include('Classe de bônus: 9.')
      expect(texto).to include('Seguradora anterior: HDI.')
      expect(texto).to include('Sinistros na vigência anterior: 1.')
    end

    it 'o seguro novo chega como seguro novo, e o bônus como não informado' do
      cotacao_pedida_com({ 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' } })

      texto = ao_modelo

      expect(texto).to include('Tipo de seguro: seguro novo, sem marcar renovação.')
      expect(texto).to include("Classe de bônus: #{Autonomia::Insurance::EntradaDaCotacao::SEM_INFORMACAO}")
    end

    # O RESUMO NÃO PODE ABRIR CRÉDITO DE PREÇO: a fala da Lia é conferida contra este texto
    # (`ConferenciaDePrecos`), e um valor em reais aqui viraria valor que ela pode escrever.
    it 'o resumo não acrescenta nenhum valor em reais ao que a Lia pode escrever' do
      conexao_com_schema
      cotacao_pedida_com(renovacao.merge('coverage' => { 'deductibleType' => 2, 'propertyDamage' => 100_000 }))

      texto = ao_modelo

      expect(texto).to include('Franquia: 100%.')
      expect(Autonomia::Agents::ConferenciaDePrecos.valores(texto))
        .to match_array(Autonomia::Agents::ConferenciaDePrecos.valores(texto.split('Com que dados').first))
    end

    it 'vem depois dos preços e fica registrado no turno para a conferência' do
      cotacao_pedida_com(renovacao)

      texto = ao_modelo

      expect(texto).to start_with('2 seguradoras fizeram proposta nesta cotação.')
      expect(texto.split("\n").last).to eq(Autonomia::Insurance::EntradaDaCotacao::AUSENCIA)
      # O RESUMO NÃO VAI À CONFERÊNCIA (revisão da PR #518): ele cita a seguradora ANTERIOR da renovação, e
      # tê-la nos dados do turno autorizaria a Lia a afirmar o desfecho dela sem nada que sustentasse.
      registrado = delivery.resultado_do_turno.texto
      expect(texto).to start_with(registrado)
      expect(registrado).not_to include('Com que dados esta cotação foi pedida')
    end

    it 'também acompanha a pergunta por uma seguradora' do
      cotacao_pedida_com(renovacao)

      expect(ao_modelo('Porto')).to include('Classe de bônus: 9.')
    end

    # SEM COTAÇÃO, NADA MUDA: não há entrada para resumir, e os estados sem leitura seguem inteiros.
    it 'sem cotação na conversa, o texto continua o mesmo' do
      expect(ao_modelo).to eq(described_class::SEM_COTACAO)
    end

    it 'cotação que não chegou às seguradoras continua sem resumo' do
      cotacao_pedida_com(renovacao, status: 'done').update!(handle: {})

      expect(ao_modelo).to eq(described_class::NAO_CHEGOU)
    end

    it 'execução sem argumentos e ramo que não é auto não ganham resumo' do
      cotacao_pedida_com({ 'produto' => 'bike', 'dados' => '{}' })

      expect(ao_modelo).not_to include('Com que dados esta cotação foi pedida')
    end
  end

  describe 'o schema' do
    let(:schema) { described_class.openai_schema }

    it 'tem um parâmetro só, seguradora, opcional pelo tipo e presente em required, sem anyOf' do
      expect(schema[:parameters][:properties].keys).to eq(['seguradora'])
      expect(schema[:parameters][:required]).to eq(['seguradora'])
      expect(schema[:parameters][:properties]['seguradora']['type']).to match_array(%w[string null])
      expect(schema.to_json).not_to include('anyOf')
      expect(schema[:strict]).to be(true)
      expect(schema[:parameters][:additionalProperties]).to be(false)
    end
  end
end
