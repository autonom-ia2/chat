require 'rails_helper'

# A FERRAMENTA DA LIA QUE VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420, desenho da rodada 8): síncrona, sobre linhas
# reais de `autonomia_agent_tool_runs`. O que o modelo lê é o texto que `call` devolve; a lista de preços é o anexo
# do turno (`Tools::Delivery#anexos`). O caminho pelo turno e pelo Responder está em
# `answerer_resultado_da_cotacao_spec`. Dados sintéticos.
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

  def itens(*ofertas)
    ofertas.map { |oferta| Autonomia::Insurance::QuoteOffers.item(oferta) }.join("\n\n")
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

  describe 'o que chega ao modelo, sem preço a anexar' do
    # Nesses estados nada é anexado ao turno.
    def ao_modelo(seguradora = nil, turno: delivery)
      super.tap { expect(turno.anexos).to be_empty }
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

  describe 'com preço a anexar' do
    it 'o resultado inteiro: o modelo lê o estado, e a lista vai anexada, escrita por QuoteOffers.item' do
      cotacao_com(status: 'running')

      texto = ao_modelo

      expect(texto.split("\n")).to eq(['2 seguradoras fizeram proposta até agora.', described_class::LISTA_ANEXADA,
                                       described_class::AINDA_CORRENDO, described_class::HA_SEM_PROPOSTA])
      expect(delivery.anexos).to eq([itens(porto, allianz)])
    end

    it 'o resultado inteiro de cotação encerrada, só com preços, sem bônus' do
      cotacao_com(status: 'done', ofertas: [porto], handle: { cotacao::SEM_BONUS_KEY => true })

      expect(ao_modelo.split("\n")).to eq(['1 seguradora fez proposta nesta cotação.', described_class::LISTA_ANEXADA,
                                           described_class::SEM_BONUS])
    end

    it 'uma seguradora com preço: só ela na lista' do
      cotacao_com(status: 'done')

      texto = ao_modelo('a porto')

      expect(texto).to include(described_class::LISTA_ANEXADA, 'Porto Seguro fez proposta: o preço dela vai na lista anexada.')
      expect(delivery.anexos).to eq([itens(porto)])
    end

    it 'uma com preço e uma sem proposta no mesmo pedido: as duas falas, e só a com preço na lista' do
      cotacao_com(status: 'done')

      texto = ao_modelo('Sancor e Porto')

      expect(texto).to include('Porto Seguro fez proposta', 'Sancor não fez proposta nesta cotação.',
                               described_class::MOTIVOS.fetch('veiculo'))
      expect(texto).not_to include(risco['text'])
      expect(delivery.anexos).to eq([itens(porto)])
    end
  end

  # O MODELO NUNCA RECEBE VALOR: varre os estados com preço e os por seguradora, e o anexo tem o valor.
  it 'nenhum texto ao modelo tem valor ou travessão, em nenhum estado; o valor está só no anexo' do
    cotacao_com(status: 'running', handle: { cotacao::SEM_BONUS_KEY => true })
    textos = [nil, 'Porto', 'Allianz', 'Sancor', 'Mitsui', 'Sancor e Porto', 'Azul'].map do |seguradora|
      ao_modelo(seguradora, turno: Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil))
    end

    expect(textos).to all(be_present)
    expect(textos.join("\n")).not_to match(/R\$|2119|2\.119|2402|2\.402|211,92|240,26|—/)
    ao_modelo
    expect(delivery.anexos.join).to include('2.119,18')
  end

  # UMA LISTA POR TURNO: a ferramenta chamada duas vezes no mesmo turno troca o próprio anexo pela lista com as
  # seguradoras das duas chamadas. Outro turno (outra pergunta do cliente) tem a lista dele.
  describe 'mais de uma chamada' do
    it 'duas chamadas no mesmo turno anexam uma lista só, com as seguradoras das duas, na ordem da lista de preços' do
      cotacao_com(status: 'done')

      ao_modelo('Allianz')
      ao_modelo('Porto')
      ao_modelo('Allianz')

      expect(delivery.anexos).to eq([itens(porto, allianz)])
    end

    it 'a mesma pergunta em dois turnos recebe a lista nos dois' do
      cotacao_com(status: 'done')
      turnos = Array.new(2) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil) }

      turnos.each { |turno| ao_modelo(nil, turno: turno) }

      expect(turnos.map(&:anexos)).to eq([[itens(porto, allianz)], [itens(porto, allianz)]])
    end
  end

  describe 'qual cotação ela lê, no instante da pergunta' do
    Autonomia::Insurance::ResultadoDaCotacao::FORA.each do |status|
      it "a mais nova que não está #{status}" do
        cotacao_com(status: 'done', ofertas: [porto], criada: 10.minutes.ago)
        cotacao_com(status: status, ofertas: [allianz], criada: 1.minute.ago)

        ao_modelo

        expect(delivery.anexos).to eq([itens(porto)])
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

      expect([primeiro.anexos, delivery.anexos]).to eq([[itens(porto)], [itens(allianz)]])
    end

    it 'não lê cotação de outra conversa' do
      outra = create(:conversation, account: account, inbox: inbox)
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: 'done',
                                         conversation_id: outra.id, execution_key: SecureRandom.uuid, arguments: {},
                                         handle: { 'quote_id' => 'q-1:1', cotacao::RESULTADO_KEY => guardar.unir({}, ofertas_padrao) })

      expect(ao_modelo).to eq(described_class::SEM_COTACAO)
    end
  end

  # O PREÇO QUE A COTAÇÃO AINDA ESTÁ ENVIANDO: o lote aceito pelo publicador e ainda não entregue na conversa não
  # entra na lista da Lia, que mostraria o mesmo preço duas vezes.
  describe 'o preço que a cotação ainda está enviando' do
    let(:bot) { create(:agent_bot, account: account) }

    # A cotação com Porto e Allianz com preço, cada uma num lote de preço, os dois emitidos há `emitidos` e aceitos
    # (`aceitos`). `entregues` são os lotes que já são mensagem na conversa; `pendentes`, os que são mensagem com
    # pendência de envio.
    def cotacao_com_lotes(entregues: [], pendentes: [], aceitos: %w[porto allianz], mapeados: true, emitidos: 1.minute)
      run = cotacao_com(status: 'running', ofertas: [porto, allianz])
      tokens = { 'porto' => "#{run.execution_key}:porto", 'allianz' => "#{run.execution_key}:allianz" }
      aceite = { cotacao::PRECOS_KEY => tokens.values, Autonomia::Agents::Tools::EntregaAceita::CHAVE => tokens.values_at(*aceitos) }
      run.update!(handle: run.handle.merge(aceite).merge(mapeados ? lotes_de(tokens, emitidos) : {}))
      (entregues + pendentes).each { |nome| mensagem_do_lote(tokens[nome], pendente: pendentes.include?(nome)) }
      run
    end

    def lotes_de(tokens, emitidos)
      lote = ->(codigo) { { 'codigos' => [codigo], 'emitido_em' => emitidos.ago.iso8601 } }
      { cotacao::Resultado::LOTES_KEY => { tokens['porto'] => lote.call('8'), tokens['allianz'] => lote.call('5') } }
    end

    def mensagem_do_lote(token, pendente:)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: bot,
                       content: 'lote', content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token,
                                                              'autonomia_envio_pendente' => pendente })
    end

    # -> a lista que um turno novo anexa para o resultado inteiro.
    def anexado
      turno = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil)
      ao_modelo(nil, turno: turno)
      turno.anexos
    end

    it 'com todos os lotes a caminho, o modelo ouve que os preços estão na fila de envio, e nada é anexado' do
      cotacao_com_lotes

      expect(ao_modelo.split("\n").last).to eq(described_class::PRECOS_A_CAMINHO)
      expect(ao_modelo('Allianz')).to include('Allianz fez proposta: o preço dela está na fila de envio e chega numa mensagem do sistema.')
      expect(delivery.anexos).to be_empty
    end

    it 'com um lote entregue e outro a caminho, a lista leva só o entregue' do
      cotacao_com_lotes(entregues: ['porto'])

      texto = ao_modelo

      expect(texto.split("\n").first(3)).to eq(['2 seguradoras fizeram proposta até agora.', described_class::LISTA_ANEXADA,
                                                described_class::PARTE_A_CAMINHO])
      expect(delivery.anexos).to eq([itens(porto)])
      expect(ao_modelo('Porto e Allianz')).to include('Porto Seguro fez proposta: o preço dela vai na lista anexada',
                                                      'Allianz fez proposta: o preço dela está na fila de envio')
    end

    it 'o lote com pendência de envio está a caminho, com aceite ou sem; o lote não aceito e sem mensagem, não' do
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'])
      expect(anexado).to eq([itens(porto)])

      Autonomia::Agents::ToolRun.delete_all
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'], aceitos: ['porto'])
      expect(anexado).to eq([itens(porto)])

      Autonomia::Agents::ToolRun.delete_all
      cotacao_com_lotes(entregues: ['porto'], aceitos: ['porto'])
      expect(anexado).to eq([itens(porto, allianz)])
    end

    it 'o lote com pendência de envio mais velha que a janela do varredor não está mais a caminho' do
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'])
      antiga = (Autonomia::Agents::Tools::ReapStaleRunsJob::ENVIO_PENDENTE_JANELA + 1.hour).ago
      conversation.messages.where(content: 'lote').find_each do |mensagem|
        mensagem.update_columns(created_at: antiga) if mensagem.content_attributes['autonomia_envio_pendente'] # rubocop:disable Rails/SkipsModelValidations
      end

      expect(anexado).to eq([itens(porto, allianz)])
    end

    it 'o lote aceito sem mensagem emitido há mais que a janela não está mais a caminho' do
      cotacao_com_lotes(entregues: ['porto'], emitidos: Autonomia::Insurance::ResultadoDaCotacao::JANELA_DO_LOTE + 1.minute)

      expect(anexado).to eq([itens(porto, allianz)])
    end

    it 'o lote a caminho sem os códigos gravados (emitido antes desta versão) segura todos os preços, dentro da janela' do
      run = cotacao_com_lotes(entregues: ['porto'], mapeados: false)
      expect(ao_modelo.split("\n").last).to eq(described_class::PRECOS_A_CAMINHO)

      run.update_columns(updated_at: (Autonomia::Insurance::ResultadoDaCotacao::JANELA_DO_LOTE + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations
      expect(anexado).to eq([itens(porto, allianz)])
    end

    it 'com todos os lotes entregues, a lista leva todos' do
      cotacao_com_lotes(entregues: %w[porto allianz])

      expect(anexado).to eq([itens(porto, allianz)])
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
