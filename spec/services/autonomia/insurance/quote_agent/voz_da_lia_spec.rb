require 'rails_helper'

# A VOZ DA LIA, os três itens aprovados pelo Rodrigo em 26/09/2026 (auditoria de 233 falas de produção):
#   9  o especialista de cotação devolve FATOS, e a fala é da Lia (`QuoteAgent::RetornoDoEspecialista`);
#   6  o aviso de fim de cotação carrega fatos secos e sabe das outras cotações do mesmo pedido;
#   5A o `item` é identificador nosso, e a Lia chama o bem como a pessoa chama.
# O que não pode mudar junto, e está provado aqui: a Lia recebe o dado que falta exatamente como o especialista o
# escreveu; a SITUAÇÃO DA COTAÇÃO continua no fim do texto; o aviso continua mandando não falar de quem ficou sem
# proposta, e os desfechos sem resultado não ganham fato de pedido nem de contagem.
RSpec.describe 'A voz da Lia' do # rubocop:disable RSpec/DescribeClass
  let(:retorno) { Autonomia::Insurance::QuoteAgent::RetornoDoEspecialista }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:lia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                     enabled: true, instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end
  let(:especialista) do
    Autonomia::Agents::Specialist.create!(agent: lia, name: 'Cotação', slug: 'cotacao_auto', description: 'cota auto',
                                          instruction: 'Você cota.')
  end
  let(:runner) { Autonomia::Agents::Specialists::Runner }
  let(:eventos) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:faixa) { Autonomia::Insurance::Faixa }

  # O modelo dublado responde no schema que o Runner pediu (`RetornoDoEspecialistaHelper`) e guarda qual foi.
  def modelo(texto_por_schema)
    pedido = {}
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs|
      pedido[:schema] = kwargs[:schema]
      { text: texto_por_schema.call(kwargs[:schema]) }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    pedido
  end

  def execucao(item: nil, status: 'done', origem: 11, handle: {}, arguments: {})
    Autonomia::Agents::ToolRun.create!(account: account, agent: lia, slug: 'cotar_seguro', status: status,
                                       faixa: faixa.de('residencial', item), conversation_id: conversation.id,
                                       origin_message_id: origem, execution_key: SecureRandom.uuid,
                                       arguments: { 'item' => item }.compact.merge(arguments), handle: handle)
  end

  describe 'item 9: o texto que a Lia lê' do
    it 'rotula cada parte, e o que falta sai com o dado exatamente como veio' do
      fatos = fatos_do_especialista(
        o_que_fez: 'Troquei o carro reserva de 20 para 30 dias.',
        pedido_que_entrou: ['franquia reduzida'],
        pedido_que_nao_coube: [{ 'pedido' => 'danos elétricos de 50 mil', 'motivo' => 'vão até 10% do incêndio' }],
        falta_perguntar: [{ 'dado' => 'CEP de pernoite', 'por_que' => 'o preço muda com a região' }, { 'dado' => 'condutor', 'por_que' => '' }],
        contexto_da_pessoa: ['é o carro da filha.', 'ela começa a dirigir semana que vem.']
      )
      texto = retorno.texto(JSON.parse(fatos))

      expect(texto.lines.first.chomp).to eq(retorno::CABECALHO)
      expect(texto).to include("O que ele fez: Troquei o carro reserva de 20 para 30 dias.\n",
                               "Pedido às seguradoras, a partir do que a pessoa pediu: franquia reduzida.\n",
                               'Do pedido da pessoa, não coube: danos elétricos de 50 mil (vão até 10% do incêndio).',
                               "#{retorno::AINDA_FALTA} CEP de pernoite (o preço muda com a região); condutor.",
                               'O que a pessoa contou de si e do pedido: é o carro da filha; ela começa a dirigir semana que vem.')
      expect(texto).not_to include('Resultado lido')
    end

    it 'sem nenhuma parte, não há texto' do
      expect(retorno.texto(JSON.parse(fatos_do_especialista))).to be_nil
    end

    it 'só os especialistas que a Autonom.ia mantém devolvem fatos' do
      outro = Autonomia::Agents::Specialist.create!(agent: lia, name: 'Agenda', slug: 'agenda', description: 'agenda',
                                                    instruction: 'Você agenda.')
      expect(retorno.aplica?(especialista)).to be(true)
      expect(retorno.aplica?(outro)).to be(false)
    end
  end

  # EM `strict`, A OPENAI RECUSA A CHAMADA INTEIRA quando um objeto tem chave fora de `required` ou aceita chave extra
  # (`Native::Base.openai_schema`). O schema dos fatos tem objetos aninhados; todos são percorridos.
  it 'item 9: todo objeto do schema dos fatos, inclusive os aninhados, é strict' do
    objetos = []
    visitar = lambda do |no|
      next unless no.is_a?(Hash)

      objetos << no if no[:type] == 'object'
      no.each_value { |valor| valor.is_a?(Array) ? valor.each { |item| visitar.call(item) } : visitar.call(valor) }
    end
    visitar.call(retorno::SCHEMA[:schema])

    expect(objetos.size).to eq(3)
    objetos.each do |objeto|
      expect(objeto[:required]).to match_array(objeto[:properties].keys.map(&:to_s))
      expect(objeto[:additionalProperties]).to be(false)
    end
  end

  describe 'item 9: o Runner' do
    it 'pede ao especialista de cotação o schema de fatos e devolve os fatos à Lia' do
      pedido = modelo(->(_schema) { fatos_do_especialista(falta_perguntar: [{ 'dado' => 'CEP de pernoite', 'por_que' => '' }]) })

      saida = runner.new(specialist: especialista, request: 'cotar o carro').call

      expect(pedido[:schema]).to eq(retorno::SCHEMA)
      expect(saida).to eq("#{retorno::CABECALHO}\n#{retorno::AINDA_FALTA} CEP de pernoite.")
    end

    # SEM REGRESSÃO FORA DA COTAÇÃO: o especialista que a corretora criou continua na prosa, com a mesma saída.
    it 'o especialista de fora da cotação continua na prosa, com a mesma saída de antes' do
      outro = Autonomia::Agents::Specialist.create!(agent: lia, name: 'Agenda', slug: 'agenda', description: 'agenda',
                                                    instruction: 'Você agenda.')
      pedido = modelo(->(schema) { resposta_do_especialista(schema, resposta: 'Consegui parte.', faltando: %w[dia hora]) })

      saida = runner.new(specialist: outro, request: 'agendar').call

      expect(pedido[:schema]).to eq(runner::RESULT_SCHEMA)
      expect(saida).to eq('Consegui parte. Ainda falta: dia, hora.')
    end

    it 'fatos vazios viram a recusa registrada de sempre' do
      modelo(->(_schema) { fatos_do_especialista })
      allow(Autonomia::Agents::Tools::Recusa).to receive(:registrar)

      expect(runner.new(specialist: especialista, request: 'cotar').call).to eq('O especialista não conseguiu concluir.')
      expect(Autonomia::Agents::Tools::Recusa).to have_received(:registrar).with('especialista_nao_concluiu', anything)
    end

    # A GUARDA DE DINHEIRO NÃO DEPENDE DA FALA DO ESPECIALISTA: tentou cotar e a conferência recusou, a SITUAÇÃO DA
    # COTAÇÃO dita pelo sistema continua no fim, depois dos fatos, e é ela que proíbe dizer que vai cotar.
    it 'a situação da cotação continua no fim, depois dos fatos' do
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 7)
      nativa = build_async_tool(slug: 'cotar_teste', precheck: 'Antes de cotar, informe o CEP.')
      allow(especialista).to receive(:tools).and_return([Autonomia::Agents::Tools::Bound.new(agent: lia, native: nativa)])
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
        executor.call([{ 'name' => 'cotar_teste', 'arguments' => '{}', 'call_id' => 'c1' }])
        { text: fatos_do_especialista(falta_perguntar: [{ 'dado' => 'CEP', 'por_que' => '' }]) }
      end
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      saida = runner.new(specialist: especialista, request: 'cotar', delivery: delivery).call

      expect(saida).to start_with(retorno::CABECALHO)
      expect(saida).to include("#{retorno::AINDA_FALTA} CEP.")
      expect(saida).to end_with(runner::COTACAO_NAO_ABERTA)
    end
  end

  # A LIA RECEBE O QUE O ESPECIALISTA DEVOLVEU, sem perda: o texto dos fatos é a saída da função que ela lê.
  describe 'item 9: o que chega à Lia no turno' do
    it 'a saída de consultar_cotacao_auto é o texto dos fatos, com o dado que falta exato' do
      especialista
      recebido = {}
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
        if schema_do_especialista?(kwargs[:schema])
          next { text: fatos_do_especialista(falta_perguntar: [{ 'dado' => 'data de nascimento do condutor', 'por_que' => 'muda o preço' }]) }
        end

        chamada = { 'name' => 'consultar_cotacao_auto', 'call_id' => 'e1', 'arguments' => { 'pedido' => 'cotar o carro' }.to_json }
        recebido[:saida] = executor.call([chamada]).first[:output]
        { text: { reply: 'Qual a data de nascimento de quem dirige?', confidence: 0.9, should_handoff: false,
                  handoff_reason: nil, used_snippet_ids: [], answered_from_knowledge: false }.to_json }
      end
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      Autonomia::Agents::Answerer.new(agent: lia, query: 'quero cotar meu carro', trust_instruction: true).answer

      expect(recebido[:saida]).to start_with(retorno::CABECALHO)
      expect(recebido[:saida]).to include("#{retorno::AINDA_FALTA} data de nascimento do condutor (muda o preço).")
    end
  end

  describe 'item 6: o aviso de fim de cotação' do
    let(:com_preco) { { eventos::DELIVERED_KEY => %w[1 2 3] } }

    it 'traz fatos secos: a contagem, o pedido que entrou e o que não coube, e mantém as regras do arquivo e de quem ficou de fora' do
      pedido = { 'pedido_que_entrou' => 'danos elétricos de 10 mil', 'pedido_que_nao_coube' => 'vendaval de 200 mil, acima do limite' }
      run = execucao(item: 'apto 302 ubatuba', handle: com_preco, arguments: pedido)

      texto = eventos.fatos_do_evento('concluida', run)

      expect(texto).to include('Situação: terminou.', 'comparativo em PDF', eventos::ORDEM_DO_ARQUIVO,
                               'Seguradoras que trouxeram preço: 3.', "#{eventos::PEDIDO_AS_SEGURADORAS} danos elétricos de 10 mil.",
                               'Do pedido da pessoa, não coube: vendaval de 200 mil, acima do limite.')
      expect(texto).to include(eventos::NEM_SEMPRE_COTADO)
      expect(texto).to end_with(eventos::SEM_QUEM_FICOU_DE_FORA)
      expect(texto).not_to include('acabou de ser enviado', 'com as opções acabou')
    end

    it 'sem preço contado, sem pedido e sem outra cotação, não inventa linha' do
      texto = eventos.fatos_do_evento('encerrada_por_prazo', execucao(item: 'casa'))

      expect(texto).not_to include('Seguradoras que trouxeram preço', 'Do pedido da pessoa', 'Outras cotações')
      expect(texto).to end_with(eventos::SEM_QUEM_FICOU_DE_FORA)
    end

    # O DINHEIRO: sem resultado não há o que contar do pedido, e contar o que entrou num desfecho sem proposta abriria
    # a porta para falar de recusa.
    it 'os desfechos sem resultado não ganham contagem, pedido nem vizinhas' do
      execucao(item: 'casa', status: 'running')
      argumentos = { 'pedido_que_entrou' => 'vendaval', 'pedido_que_nao_coube' => 'roubo de bike' }
      %w[sem_aceitacao falhou incerta].each do |tipo|
        texto = eventos.fatos_do_evento(tipo, execucao(item: "apto #{tipo}", handle: com_preco, arguments: argumentos))
        expect(texto).not_to include('Seguradoras que trouxeram preço', 'Do pedido da pessoa', 'Outras cotações')
      end
    end

    it 'sabe das outras cotações do mesmo pedido, e se cada uma já foi contada à pessoa' do
      contada = execucao(item: 'casa campinas', handle: { Autonomia::Agents::Tools::Evento::FECHO_KEY => 'concluida' })
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'saiu',
                       content_attributes: { Autonomia::Agents::Tools::Evento::CHAVE => "#{contada.id}:concluida" })
      execucao(item: 'onix', status: 'running')
      execucao(item: 'terreno', handle: { Autonomia::Agents::Tools::Evento::FECHO_KEY => 'concluida' })
      execucao(item: 'antiga', status: 'superseded')
      execucao(item: 'barrada', status: 'blocked')
      execucao(item: 'de outra mensagem', origem: 99)
      atual = execucao(item: 'apto 302 ubatuba', handle: com_preco)

      texto = Autonomia::Insurance::CotacoesDoMesmoPedido.fatos(atual)

      expect(texto).to start_with('Outras cotações pedidas na mesma mensagem da pessoa: ')
      expect(texto).to include('casa campinas (produto: residencial:casa campinas), já contada à pessoa',
                               'onix (produto: residencial:onix), ainda correndo',
                               'terreno (produto: residencial:terreno), terminou')
      expect(texto).not_to include('antiga', 'barrada', 'de outra mensagem', 'apto 302')
      expect(texto).to end_with(Autonomia::Insurance::CotacoesDoMesmoPedido::OUTRA_ABERTURA)
      expect(eventos.fatos_do_evento('concluida', atual)).to include(texto)
    end

    it 'a leitura das outras cotações que falha não leva junto o resto do aviso' do
      allow(Autonomia::Agents::ToolRun).to receive(:for_conversation).and_raise(ActiveRecord::StatementInvalid)
      texto = eventos.fatos_do_evento('concluida', execucao(item: 'casa', handle: com_preco))

      expect(texto).to include('Seguradoras que trouxeram preço: 3.')
      expect(texto).to end_with(eventos::SEM_QUEM_FICOU_DE_FORA)
    end
  end

  describe 'item 5A: o nome do bem' do
    it 'o item aparece como identificador nosso, seguido de como chamar o bem, sem mudar a chave' do
      run = execucao(item: 'Apto 302 Ubatuba')

      expect(run.faixa).to eq('residencial:apto 302 ubatuba')
      expect(faixa.descricao(run)).to eq('residencial, bem de identificador Apto 302 Ubatuba (produto: residencial:apto 302 ubatuba)')
      expect(eventos.fatos_do_evento('falhou', run))
        .to start_with("Cotação de #{faixa.descricao(run)}. #{faixa::NOME_NA_CONVERSA} ")
    end

    it 'sem item (execução de antes da chat#612), nem identificador nem a frase' do
      run = Autonomia::Agents::ToolRun.new(faixa: 'auto', handle: {}, arguments: {})

      expect(eventos.fatos_do_evento('falhou', run)).to start_with('Cotação de auto. A cotação não pôde')
      expect(eventos.fatos_do_evento('falhou', run)).not_to include(faixa::NOME_NA_CONVERSA)
    end

    it 'a situação da cotação aberta pelo especialista também diz como chamar o bem' do
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 7)
      nativa = build_async_tool(slug: 'cotar_teste')
      allow(especialista).to receive(:tools).and_return([Autonomia::Agents::Tools::Bound.new(agent: lia, native: nativa)])
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
        executor.call([{ 'name' => 'cotar_teste', 'arguments' => { 'item' => 'Onix da esposa' }.to_json, 'call_id' => 'c1' }])
        { text: fatos_do_especialista(o_que_fez: 'Abri a cotação do Onix.') }
      end
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      saida = runner.new(specialist: especialista, request: 'cotar', delivery: delivery).call

      expect(saida).to include(runner::COTACAO_ABERTA, 'bem de identificador Onix da esposa', faixa::NOME_NA_CONVERSA)
    end
  end
end
