require 'rails_helper'

# O ENCERRAMENTO, PASSO A PASSO (entrega 8).
#
# Ele é a ÚLTIMA coisa que acontece numa execução que acabou sem fechar, e a marca `closed` que ele
# adquire no primeiro passo garante que ninguém volta aqui. Isso faz de cada passo seguinte um
# caminho sem segunda chance: o que se perder ali, o cliente perde para sempre. Daí as três
# propriedades que este arquivo trava:
#
#   - CADA PASSO CAI SOZINHO. Um `rescue` cobrindo entregar e fechar deixava o cliente MUDO quando o
#     passo que consulta o banco (e, na cotação, o portal) levantava — o mesmo tipo de erro que
#     abandona a linha. Agora o fecho é publicado de qualquer jeito.
#   - UMA ENTREGA NÃO DERRUBA AS OUTRAS. Com o lote inteiro dentro de um tratamento só, a segunda
#     entrega levantando apagava a primeira: o fecho publicava a frase de falha logo depois de uma
#     publicação bem-sucedida.
#   - A FRASE PARCIAL SÓ SAI QUANDO É VERDADE. Ela saía por `delivered_count.positive?`, e esse
#     contador conta qualquer item aceito para publicação — um aviso, a pergunta pelo dado que
#     falta. Agora são DUAS perguntas à ferramenta (houve resultado? sobrou algo?), e sem as duas
#     volta o SILÊNCIO: frase nenhuma é melhor que frase falsa.
RSpec.describe Autonomia::Agents::Tools::Encerramento do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  # A execução como o encerramento a encontra: promovida, com o handle do trabalho e com o contador
  # de entregas que o motor foi acumulando.
  def execucao(handle: {}, entregas: 0)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run.merge_handle!(handle) if handle.present?
    entregas.times { run.record_delivery! }
    run
  end

  # Publicação FORÇADA, como a do varredor: é o caminho em que o fecho é a última palavra que o
  # cliente recebe, e o que este arquivo precisa observar.
  def encerrar(run, tool, trabalho_novo: true, &publicador)
    register_async_tool(tool)
    publicador ||= ->(entrega) { Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega) }
    described_class.new(run: run, native: tool, trabalho_novo: trabalho_novo, &publicador).encerrar
  end

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  describe 'cada passo cai sozinho, e o fecho é a última coisa' do
    # O PASSO QUE CONSULTA PODE FALHAR — e falha exatamente onde dói: a linha foi abandonada porque
    # algo quebrou, e `closing_deliveries` vai ao banco (e, na cotação, ao portal). Com um `rescue`
    # só, a exceção pulava o fecho com a marca `closed` já gravada: nenhuma passada futura reentra,
    # e o cliente que esperava ficava sem uma palavra para sempre.
    it 'a ferramenta que levanta ao montar as entregas nao cala o fecho' do
      # Arrange
      run = execucao
      tool = build_async_tool(closing: -> { raise ActiveRecord::StatementInvalid, 'banco fora' })

      # Act
      entregou = encerrar(run, tool)

      # Assert — nada entregue, mas o cliente lê a frase de falha
      expect(entregou).to be(false)
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # UMA ENTREGA NÃO DERRUBA AS OUTRAS, NEM APAGA O QUE JÁ SAIU (Codex). Com o `map` inteiro dentro
    # de um tratamento só, a exceção na SEGUNDA entrega fazia o passo devolver `false`: as entregas
    # do encerramento não contam em `delivered_count`, então o fecho publicava a frase de FALHA logo
    # depois de uma publicação bem-sucedida — negando ao cliente o arquivo que ele acabara de receber.
    #
    # O caminho é real e é o do próprio motor: `AsyncRunJob#publish` re-agenda a entrega ADIADA com
    # `AsyncPublishJob.perform_later`, e enfileirar levanta com o Redis fora — que é uma das avarias
    # que levam a execução a acabar sem fechar, para começo de conversa.
    it 'a entrega que levanta nao apaga a que ja foi publicada, nem vira frase de falha' do
      # Arrange
      run = execucao
      tool = build_async_tool(closing: ['o primeiro arquivo', 'o segundo arquivo'], resultado: true, resta: true)
      publicador = lambda do |entrega|
        raise 'enfileirar a adiada falhou' if entrega == 'o segundo arquivo'

        Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
      end

      # Act
      entregou = encerrar(run, tool, &publicador)

      # Assert — a primeira ficou, e o fecho é o de quem recebeu algo
      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o primeiro arquivo', tool.partial_message])
    end

    # TODAS AS ENTREGAS SAEM, não só a primeira. O passo devolve "alguma foi aceita?", e responder
    # isso com um `any?` pararia na primeira aceita — a segunda ficaria no handle para sempre, que é
    # o defeito que o encerramento existe para não ter.
    it 'publica todas as entregas do encerramento, e nao para na primeira' do
      run = execucao
      tool = build_async_tool(closing: ['o primeiro arquivo', 'o segundo arquivo'], resultado: true, resta: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o primeiro arquivo', 'o segundo arquivo', tool.partial_message])
    end

    # E A ORDEM SEGUE: a entrega que levanta não impede a SEGUINTE de sair. Quem para no primeiro
    # erro perde tudo o que vinha depois, e não há passada futura para recuperar.
    it 'a entrega que levanta nao impede a seguinte' do
      run = execucao
      tool = build_async_tool(closing: ['o que caiu', 'o que ficou pronto'], resultado: true, resta: true)
      publicador = lambda do |entrega|
        raise 'enfileirar a adiada falhou' if entrega == 'o que caiu'

        Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
      end

      encerrar(run, tool, &publicador)

      expect(bot_contents).to eq(['o que ficou pronto', tool.partial_message])
    end

    # A MARCA É ADQUIRIDA ANTES DE TUDO, E ISSO TEM PREÇO. Quem não adquire não publica NADA — nem o
    # fecho —, porque quem adquiriu já está publicando: dois encerradores sobre a mesma linha (o
    # retry do Sidekiq depois de um hard shutdown, o varredor cruzando com o motor) publicariam duas
    # vezes. O reverso é o que este exemplo trava: uma segunda passada não conserta a primeira.
    it 'a segunda passada na mesma linha nao adquire a marca e nao publica nada' do
      # Arrange
      run = execucao
      tool = build_async_tool

      # Act — a primeira publica o fecho; a segunda encontra a marca já gravada
      encerrar(run, tool)
      de_novo = encerrar(run.reload, tool)

      # Assert
      expect(de_novo).to be(false)
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # O encerramento continua sendo cortesia sobre um caminho que já deu errado: ele não levanta,
    # porque quem chama ainda precisa registrar o desfecho (`finish!`).
    it 'nao levanta quando tudo falha ao mesmo tempo' do
      run = execucao
      tool = build_async_tool(closing: -> { raise 'entregas' })
      tool.define_method(:resultado_entregue?) { |_handle| raise 'fecho' }

      expect { encerrar(run, tool) }.not_to raise_error
    end
  end

  describe 'a frase parcial só sai quando é verdade' do
    # O CONTADOR NÃO SIGNIFICA "RESULTADO". Ele conta qualquer item aceito para publicação — na
    # cotação, `handle['pedido']` (a pergunta pelo dado que falta) é devolvido como entrega e conta.
    # Fechar com "o que chegou está aqui em cima" depois de só ter perguntado dados é descrever uma
    # tela que o cliente não está vendo.
    it 'contador positivo sem resultado fecha em SILENCIO' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resta: true))

      expect(bot_contents).to be_empty
    end

    # E RESULTADO SEM SOBRA TAMBÉM: é a cotação cujo portal já tinha fechado e cujo comparativo já
    # tinha saído, com a corrente de jobs rompida entre a gravação do handle e o `finish!`. Dizer
    # "algumas seguradoras não responderam a tempo" a quem recebeu tudo é mentir.
    it 'resultado sem sobra fecha em SILENCIO' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resultado: true))

      expect(bot_contents).to be_empty
    end

    # As duas juntas é o caso que a frase descreve: chegou alguma coisa, e alguma coisa ficou.
    it 'com resultado E sobra, a frase parcial sai' do
      run = execucao(entregas: 1)
      tool = build_async_tool(resultado: true, resta: true)

      encerrar(run, tool)

      expect(bot_contents).to eq([tool.partial_message])
    end

    # CONTADOR ZERO CONTINUA COMO ANTES: sem nada entregue, o cliente precisa de uma palavra — e ela
    # não depende de ferramenta nenhuma responder (é frase de classe).
    it 'sem nada entregue, a frase de falha' do
      run = execucao

      encerrar(run, build_async_tool(resultado: true, resta: true))

      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # Quem pode ter uma cotação correndo no portal sem registro nosso (entrega 5) não lê "não
    # consegui": lê que não há confirmação.
    it 'sem nada entregue e com envio incerto, a frase de incerteza' do
      run = execucao(handle: { Autonomia::Agents::ToolRun::INTENCOES => 1 })

      encerrar(run, build_async_tool)

      expect(bot_contents).to eq(['não consegui confirmar o envio'])
    end

    # A entrega DO ENCERRAMENTO vale como "algo chegou agora" para sair do ramo da falha — mas
    # continua sem bastar para a frase parcial, que é sobre o que FALTA.
    it 'a entrega do proprio encerramento tira a frase de falha, e nao inventa a parcial' do
      run = execucao
      tool = build_async_tool(closing: ['o arquivo que ficou pronto'], resultado: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o arquivo que ficou pronto'])
    end
  end

  # O VARREDOR NÃO COMEÇA TRABALHO NOVO NO PORTAL. Ele varre até 500 linhas em
  # sequência dentro de um cron, e o Sidekiq desta instalação tem 25 s de shutdown: quem é morto no
  # meio deixa a linha em curso com a marca `closed` e sem fecho, para sempre. Quem decide o que
  # ainda dá para entregar é a ferramenta — mas ela precisa saber em que caminho está.
  describe 'o aviso de que não se começa trabalho novo' do
    def perguntou(permitido)
      visto = []
      tool = build_async_tool
      tool.define_method(:closing_deliveries) do |_handle, trabalho_novo: true|
        visto << trabalho_novo
        []
      end
      encerrar(execucao, tool, trabalho_novo: permitido)
      visto
    end

    it 'diz à ferramenta se esta passada pode iniciar trabalho novo' do
      expect(perguntou(false)).to eq([false])
      expect(perguntou(true)).to eq([true])
    end
  end
end
