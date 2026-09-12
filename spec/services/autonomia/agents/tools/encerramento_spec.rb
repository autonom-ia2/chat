require 'rails_helper'

# O ENCERRAMENTO, PASSO A PASSO (rodada 6 da entrega 8, P1-A e P1-B).
#
# Ele é a ÚLTIMA coisa que acontece numa execução que acabou sem fechar, e a marca `closed` que ele
# adquire no primeiro passo garante que ninguém volta aqui. Isso faz de cada passo seguinte um
# caminho sem segunda chance: o que se perder ali, o cliente perde para sempre.
#
# Dois defeitos da rodada 5 moram neste arquivo:
#   - P1-A: um `rescue` só cobria entregar, anotar e fechar. Até a rodada 4 o fecho era uma frase de
#     CLASSE (sem banco, sem portal) e não tinha como falhar; a rodada 5 pôs consultas e uma ESCRITA
#     antes dele, e aí um erro de banco — o mesmo tipo de erro que abandona a linha — deixava o
#     cliente MUDO. Agora cada passo cai sozinho e o fecho é publicado de qualquer jeito.
#   - P1-B: o fecho parcial saía por `delivered_count.positive?`, e esse contador conta qualquer
#     item aceito para publicação — um aviso, a pergunta pelo dado que falta, a única proposta que o
#     cliente pediu e recebeu. Agora são DUAS perguntas à ferramenta (houve resultado? sobrou algo?),
#     e sem as duas volta o SILÊNCIO: frase nenhuma é melhor que frase falsa.
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
  def encerrar(run, tool, trabalho_novo: true)
    register_async_tool(tool)
    publicador = ->(entrega) { Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega) }
    described_class.new(run: run, native: tool, trabalho_novo: trabalho_novo, &publicador).encerrar
  end

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  describe 'cada passo cai sozinho, e o fecho é a última coisa (P1-A)' do
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

    # E O PASSO QUE ESCREVE TAMBÉM: `confirmar_publicadas` anota no banco o que virou mensagem
    # (a proposta individual marca a cotação). A anotação é registro nosso; a entrega já saiu e o
    # fecho ainda tem de sair.
    it 'a ferramenta que levanta ao anotar nao cala o fecho, e a entrega ja publicada fica' do
      # Arrange
      run = execucao
      tool = build_async_tool(closing: ['o arquivo que ficou pronto'], resultado: true, resta: true)
      tool.define_method(:confirmar_publicadas) { |_handle| raise ActiveRecord::StatementInvalid, 'banco fora' }

      # Act
      entregou = encerrar(run, tool)

      # Assert
      expect(entregou).to be(true)
      expect(bot_contents).to eq(['o arquivo que ficou pronto', tool.partial_message])
    end

    # O encerramento continua sendo cortesia sobre um caminho que já deu errado: ele não levanta,
    # porque quem chama ainda precisa registrar o desfecho (`finish!`).
    it 'nao levanta quando tudo falha ao mesmo tempo' do
      run = execucao
      tool = build_async_tool(closing: -> { raise 'entregas' })
      tool.define_method(:confirmar_publicadas) { |_handle| raise 'anotacao' }
      tool.define_method(:resultado_entregue?) { |_handle| raise 'fecho' }

      expect { encerrar(run, tool) }.not_to raise_error
    end
  end

  describe 'a frase parcial só sai quando é verdade (P1-B)' do
    # O CONTADOR NÃO SIGNIFICA "RESULTADO". Ele conta qualquer item aceito para publicação — na
    # cotação, `handle['pedido']` (a pergunta pelo dado que falta) é devolvido como entrega e conta.
    # Fechar com "o que chegou está aqui em cima" depois de só ter perguntado dados é descrever uma
    # tela que o cliente não está vendo.
    it 'contador positivo sem resultado fecha em SILENCIO' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resta: true))

      expect(bot_contents).to be_empty
    end

    # E RESULTADO SEM SOBRA TAMBÉM: é o cliente que pediu UMA proposta, recebeu essa uma e teve a
    # corrente de jobs quebrada. "Não consegui enviar todas as propostas a tempo" — todas foram.
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

  # O VARREDOR NÃO COMEÇA TRABALHO NOVO NO PORTAL (rodada 6, P2-E). Ele varre até 500 linhas em
  # sequência dentro de um cron, e o Sidekiq desta instalação tem 25 s de shutdown: quem é morto no
  # meio deixa a linha em curso com a marca `closed` e sem fecho, para sempre. Quem decide o que
  # ainda dá para entregar é a ferramenta — mas ela precisa saber em que caminho está.
  describe 'o aviso de que não se começa trabalho novo (P2-E)' do
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
