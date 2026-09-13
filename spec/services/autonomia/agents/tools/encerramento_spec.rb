require 'rails_helper'

# O ENCERRAMENTO, PASSO A PASSO (entrega 8).
#
# Ele é a ÚLTIMA coisa que acontece numa execução que acabou sem fechar, e a marca `closed` que ele
# adquire no primeiro passo impede que o TRABALHO se repita — não que a palavra ao cliente saia.
# Cada passo é, ainda assim, um caminho estreito: o que se perder ali, o cliente perde. Daí as
# quatro propriedades que este arquivo trava:
#
#   - CADA PASSO CAI SOZINHO. Um `rescue` cobrindo entregar e fechar deixava o cliente MUDO quando o
#     passo que consulta o banco (e, na cotação, o portal) levantava — o mesmo tipo de erro que
#     abandona a linha. Agora o fecho é publicado de qualquer jeito.
#   - O FECHO TEM SEGUNDA CHANCE, E NÃO DUPLICA. A marca gravada antes da publicação fazia a passada
#     seguinte (o retry do Sidekiq, o varredor) sair calada: morto o processo no meio, o cliente
#     ficava sem resultado e sem desfecho, para sempre. Agora o passo pergunta à CONVERSA se o fecho
#     desta execução já está lá.
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
    # só, a exceção pulava o fecho — e pela porta do motor não há segunda chance: o `fail_run`
    # chama o `finish!` logo em seguida, a linha vira terminal e o varredor (que só varre `running`)
    # nunca mais a vê. O cliente que esperava ficava sem uma palavra. É a guarda irmã da segunda
    # chance do fecho: uma cobre a exceção, a outra cobre o processo morto.
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
      expect(bot_contents).to eq(['o primeiro arquivo', tool.closing_message])
    end

    # TODAS AS ENTREGAS SAEM, não só a primeira. O passo devolve "alguma foi aceita?", e responder
    # isso com um `any?` pararia na primeira aceita — a segunda ficaria no handle para sempre, que é
    # o defeito que o encerramento existe para não ter.
    it 'publica todas as entregas do encerramento, e nao para na primeira' do
      run = execucao
      tool = build_async_tool(closing: ['o primeiro arquivo', 'o segundo arquivo'], resultado: true, resta: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o primeiro arquivo', 'o segundo arquivo', tool.closing_message])
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

      expect(bot_contents).to eq(['o que ficou pronto', tool.closing_message])
    end

    # A MARCA IMPEDE O TRABALHO DUAS VEZES, NÃO A PALAVRA DUAS VEZES. Dois encerradores sobre a
    # mesma linha (o retry do Sidekiq depois de um hard shutdown, o varredor cruzando com o motor)
    # não podem gerar dois comparativos — mas o SEGUNDO fecho não é uma segunda mensagem: ele é a
    # mesma, e a pergunta pela mensagem publicada impede a duplicata.
    it 'a segunda passada na mesma linha nao repete o fecho que ja saiu' do
      # Arrange
      run = execucao
      tool = build_async_tool

      # Act — a primeira publica o fecho; a segunda encontra a marca gravada E o fecho na conversa
      encerrar(run, tool)
      de_novo = encerrar(run.reload, tool)

      # Assert
      expect(de_novo).to be(false)
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # E A PASSADA SEGUINTE CONSERTA A PRIMEIRA QUE MORREU NO MEIO. É o estado que a marca criava e
    # não resolvia: adquirida antes de tudo, um processo morto entre ela e o fecho (um deploy, com
    # os 25 s de shutdown do Sidekiq; até um minuto quando o passo das entregas chama o portal)
    # deixava a linha `running`, o cliente sem resultado e sem desfecho — e nem o retry do Sidekiq
    # nem o varredor tentavam de novo, porque a marca os fazia sair calados.
    #
    # O TRABALHO NÃO SE REFAZ: a marca continua valendo para ele.
    it 'marca posta e fecho ausente: a passada seguinte fecha, e nao refaz o trabalho' do
      # Arrange — a marca de quem morreu antes de publicar
      run = execucao
      chamadas = 0
      tool = build_async_tool
      tool.define_method(:closing_deliveries) do |_handle, **|
        chamadas += 1
        ['o arquivo que a primeira passada geraria de novo']
      end
      # As CHAVES importam: sem elas o hash vira keyword em vez de argumento posicional.
      run.merge_handle!({ described_class::CLOSED_KEY => true })

      # Act
      encerrar(run.reload, tool)

      # Assert — o cliente recebe a palavra que faltava, e o portal não é consultado de novo
      expect(chamadas).to eq(0)
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # E A SEGUNDA PASSADA NÃO CONTRADIZ A PRIMEIRA. Ela não refaz as entregas — a marca está posta
    # —, então lê `entregou` como falso e escolheria OUTRA frase: a de falha, logo depois de o
    # cliente ter recebido o arquivo e a frase parcial. A dedupe por token do publicador não pegaria
    # isso (são textos diferentes, duas mensagens); quem pega é a pergunta pelo fecho já publicado.
    it 'a passada seguinte nao contradiz o fecho que ja saiu' do
      # Arrange — nada contado na linha: é o estado em que as duas passadas discordam
      run = execucao
      tool = build_async_tool(closing: ['o arquivo que ficou pronto'], resultado: true, resta: true)

      # Act
      encerrar(run, tool)
      encerrar(run.reload, tool)

      # Assert
      expect(bot_contents).to eq(['o arquivo que ficou pronto', tool.closing_message])
    end

    # MENSAGEM NO BANCO COM ENVIO PENDENTE NÃO É FECHO ENTREGUE (rodada 4).
    #
    # O publicador deixa a mensagem no banco MARCADA quando o `SendReplyJob` dela não entra na fila
    # (o Redis fora no meio da publicação): ela existe, o cliente não a recebeu. A pergunta pelo
    # fecho já publicado enxergava só a existência — a passada seguinte saía calada, e o cliente
    # ficava sem desfecho até o varredor passar.
    #
    # PUBLICAR DE NOVO É O CERTO, E NÃO DUPLICA: a dedupe por conteúdo do publicador acha a mesma
    # mensagem pelo token e RETOMA o envio dela, sob o lock.
    it 'o fecho com envio pendente e retomado pela passada seguinte, sem duplicar a mensagem' do
      # Arrange — a fila recusa o envio ao canal; a mensagem do fecho fica marcada
      run = execucao
      tool = build_async_tool
      fila_recusa_o_envio
      encerrar(run, tool)
      pendente = conversation.messages.reload.where(sender_type: 'AgentBot').last
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio.pendente?(pendente)).to be(true)

      # Act — o Redis volta e a passada seguinte (retry do Sidekiq, varredor) encontra a linha
      fila_volta
      encerrar(run.reload, tool)

      # Assert — uma mensagem só, e o envio dela entrou na fila
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio.marcada?(pendente.reload)).to be(false)
    end

    # A ENTREGA QUE O PUBLICADOR RECUSA NÃO É ENTREGA. `AsyncPublisher#publish` nunca levanta: ele
    # devolve `blocked` (autorização recusada sob o lock, conversa que já não aceita, exceção
    # engolida). Ler qualquer resultado como sucesso faria o fecho calar — ou pior, afirmar — para
    # quem não recebeu nada; o certo é a frase de falha, que é o que ele lia antes de haver
    # encerramento.
    it 'a entrega recusada pelo publicador nao conta, e o fecho e o da falha' do
      # Arrange
      run = execucao
      tool = build_async_tool(closing: ['o arquivo que ficou pronto'])
      publicador = lambda do |entrega|
        next Autonomia::Agents::Tools::AsyncPublisher::Result.new(status: :blocked) if entrega.include?('arquivo')

        Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
      end

      # Act
      entregou = encerrar(run, tool, &publicador)

      # Assert
      expect(entregou).to be(false)
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

    # A PERGUNTA "ESTE FECHO JÁ SAIU?" PASSOU A PODER LEVANTAR (12/09/2026). Até aqui ela só lia
    # constantes de classe; agora resolve a frase a partir dos argumentos da execução. Ela roda
    # DENTRO de `etapa('fecho')`, cujo `rescue` engole tudo: levantando sem tratamento própria,
    # `publicar_fecho` nunca rodaria e o cliente ficaria sem uma palavra — o buraco de silêncio que
    # a entrega 8a fechou, reaberto pela resolução.
    #
    # NÃO SEI É PUBLICAR, e o lado conservador aqui é o contrário do de sempre: a dedupe por token
    # do publicador pega o duplicado; nada pega o silêncio.
    it 'a resolucao da frase que levanta nao cala o fecho: sai a constante da classe' do
      run = execucao
      tool = build_async_tool
      tool.define_singleton_method(:failure_message) do |arguments = nil|
        raise 'resolucao da frase caiu' if arguments

        'não consegui concluir a consulta'
      end

      encerrar(run, tool)

      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    # A OUTRA METADE DA MESMA GARANTIA: a pergunta vai ao BANCO, e o banco cai. Com ela levantando
    # dentro de `etapa('fecho')`, `publicar_fecho` nunca roda e o cliente fica sem uma palavra —
    # publicar de novo, no pior caso, é a dedupe por token do publicador achando a mesma mensagem.
    it 'a pergunta pelo fecho ja publicado que levanta nao cala o fecho' do
      run = execucao
      tool = build_async_tool
      allow(Autonomia::Agents::Tools::EntregaPublicada)
        .to receive(:publicada?).and_raise(ActiveRecord::StatementInvalid, 'banco fora')

      encerrar(run, tool)

      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end
  end

  describe 'o fecho de quem tem resultado só sai quando é verdade' do
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
    it 'com resultado E sobra, o fecho de quem tem resultado sai' do
      run = execucao(entregas: 1)
      tool = build_async_tool(resultado: true, resta: true)

      encerrar(run, tool)

      expect(bot_contents).to eq([tool.closing_message])
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
    it 'a entrega do proprio encerramento tira a frase de falha, e nao inventa o fecho com resultado' do
      run = execucao
      tool = build_async_tool(closing: ['o arquivo que ficou pronto'], resultado: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o arquivo que ficou pronto'])
    end
  end

  # O VARREDOR NÃO COMEÇA TRABALHO NOVO NO PORTAL. Ele varre até 500 linhas em
  # sequência dentro de um cron, e o Sidekiq desta instalação tem 25 s de shutdown: quem é morto no
  # meio joga o resto das linhas para a varredura seguinte, 10 min depois. Quem decide o que
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
