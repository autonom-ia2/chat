require 'rails_helper'

# A ORDEM QUE PROTEGE O DINHEIRO (entrega 5). O job anota a INTENÇÃO de submeter antes de chamar o
# portal e o NÚMERO depois; quem volta e encontra intenção sem número tenta no máximo mais UMA vez,
# marcando a execução como possivelmente duplicada.
#
# A FRONTEIRA É A CHAMADA PAGA. Falha antes dela, ou com o portal dizendo que recusou, volta a
# intenção atrás (a conversa não trava por um login intermitente). Falha DEPOIS de a chamada sair,
# sem o portal dizer nada — `Native::EnvioIncerto` —, mantém a intenção: o portal pode ter cotado.
# Sinal de desligamento (`Sidekiq::Shutdown`, que é `Interrupt`) não passa por rescue nenhum: a
# intenção fica.
#
# AS ESCRITAS SÃO COMPARE-AND-SET sobre a POSSE da passada — a linha ainda na intenção lida E sem
# número — e MESCLADAS no banco, nunca copiadas da memória: a linha que mudou de dono no meio da
# passada (pedido novo, ou outro processo com a mesma execução) não é chamada no portal nem
# sobrescrita, e um objeto velho não apaga o número nem a marca que outro processo gravou.
#
# PROVA POR MUTAÇÃO (10/09/2026): subir `MAXIMO_DE_INTENCOES` para 60 reprova "na terceira intenção,
# para"; anotar depois do `start` reprova "anota a intenção antes"; `rescue Exception` em
# `tentar_start` reprova "no desligamento"; voltar a intenção atrás também no `EnvioIncerto` reprova
# "envio incerto"; posse sem `intencao` reprova "a linha mudou de dono"; posse sem a condição de
# número ausente reprova "registrou o número antes"; o desfecho sem recarregar reprova "objeto velho
# no desfecho"; o `finish!` sem marcar reprova "o desfecho marca mesmo assim"; tirar a guarda do
# número em `envio_incerto?` reprova "não marca a abandonada que tem número".
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
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
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:intencoes) { Autonomia::Agents::ToolRun::INTENCOES }
  let(:duplicada) { Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA }
  let(:submetido) { described_class::SUBMITTED_KEY }
  let(:incerto) { Autonomia::Agents::Tools::Native::EnvioIncerto }
  let(:progress) { Autonomia::Agents::Tools::Progress }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  def abrir
    runs.open!(agent: agent, slug: 'consultar_cotacao', arguments: { 'placa' => 'ABC1D23' },
               scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
  end

  # Execução promovida, como o Responder deixa no fim do turno. `handle` é o estado em que a
  # passada começa: vazio (primeira vez) ou com intenção sem número (o worker morreu no meio).
  def execucao(handle: {})
    run = abrir
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.merge_handle!(handle) if handle.present?
    run
  end

  # Uma ferramenta cujo `start` roda o bloco dado (com o contador de chamadas) e devolve o handle.
  def ferramenta_com_start(&)
    build_async_tool(handle: { 'id' => 'cot-1' }, poll: progress.running).tap do |tool|
      tool.define_method(:start, &)
    end
  end

  describe 'a ordem' do
    it 'anota a intencao ANTES de submeter e o numero DEPOIS' do
      # Arrange — a ferramenta OLHA a linha ao submeter: é assim que se prova a ordem
      run = execucao
      visto = []
      linha = runs
      register_async_tool(ferramenta_com_start do
        visto << linha.find(run.id).handle
        { 'id' => 'cot-1' }
      end)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — no momento do `start`, a linha já dizia "intenção 1" e ainda não dizia "submetido"
      expect(visto).to eq([{ intencoes => 1 }])
      expect(run.reload.handle).to include(submetido => true, 'id' => 'cot-1', intencoes => 1)
      expect(run.handle).not_to have_key(duplicada)
      expect(run.attempts).to eq(1)
    end

    it 'o que a ferramenta devolve nao escreve marca nenhuma' do
      run = execucao
      register_async_tool(build_async_tool(handle: { 'id' => 'cot-1', intencoes => 99, submetido => false }))

      described_class.new.perform(run.id, 0)

      expect(run.reload.handle).to include(submetido => true, intencoes => 1)
    end
  end

  describe 'intencao sem numero (o worker morreu entre o envio e o registro)' do
    it 'tenta no maximo mais UMA vez, e marca como possivelmente duplicada' do
      # Arrange — a passada anterior anotou a intenção e morreu antes do número
      run = execucao(handle: { intencoes => 1 })
      register_async_tool(build_async_tool(handle: { 'id' => 'cot-2' }))

      # Act
      described_class.new.perform(run.id, 0)

      # Assert
      expect(run.reload.handle).to include(submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true)
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(described_class).to have_been_enqueued.with(run.id, 1)
    end

    it 'na terceira intencao, PARA: nunca sessenta' do
      # Arrange — já houve a repetição permitida, e o número de novo não chegou
      run = execucao(handle: { intencoes => 2, duplicada => true })
      chamadas = 0
      register_async_tool(ferramenta_com_start do
        chamadas += 1
        { 'id' => 'cot-3' }
      end)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — o portal NÃO é chamado; o cliente lê que não há confirmação; a marca fica
      expect(chamadas).to eq(0)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'envio_incerto')
      expect(run.handle).to include(duplicada => true)
      expect(bot_contents).to eq(['não consegui confirmar o envio'])
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe 'falha ANTES da chamada paga, ou com o portal dizendo que recusou' do
    it 'volta a intencao atras: a conversa nao trava por um login intermitente' do
      # Arrange — o login levanta antes de `quote_start`
      run = execucao
      register_async_tool(build_async_tool(start_error: 'AGGER login: no token in response, twice'))

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — sem intenção anotada, sem marca de duplicata, e a execução segue viva
      expect(run.reload.handle).to eq({})
      expect(run.status).to eq('running')
      expect(described_class).to have_been_enqueued.with(run.id, 1)
    end

    it 'volta de 2 para 1 e MANTEM a marca: a primeira chamada segue incerta' do
      # Arrange — a primeira chamada ficou sem resposta; a segunda o portal recusou com certeza
      run = execucao(handle: { intencoes => 1 })
      register_async_tool(build_async_tool(start_error: 'credencial recusada'))

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — a marca é monotônica: tirá-la apagaria a que um desfecho concorrente acabou de gravar
      expect(run.reload.handle).to eq(intencoes => 1, duplicada => true)
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(described_class).to have_been_enqueued.with(run.id, 1)
    end

    it 'a passada seguinte submete como primeira intencao, sem marca de duplicata' do
      run = execucao
      register_async_tool(build_async_tool(handle: { 'id' => 'cot-4' }))

      described_class.new.perform(run.id, 1)

      expect(run.reload.handle).to include(submetido => true, intencoes => 1)
      expect(run.handle).not_to have_key(duplicada)
    end
  end

  # O achado da revisão de 10/09/2026: timeout do connector DEPOIS de o portal ter criado a cotação
  # era lido como "não fez", a intenção era apagada, e a passada seguinte cotava de novo sem marca.
  describe 'envio incerto: a chamada paga saiu e o portal nao disse nada' do
    it 'mantem a intencao, e a passada seguinte repete UMA vez, marcada' do
      # Arrange — 1ª chamada: timeout (o portal pode ter criado cot-1); 2ª: responde
      run = execucao
      chamadas = 0
      erro = incerto.new(:timeout)
      register_async_tool(ferramenta_com_start do
        chamadas += 1
        raise erro if chamadas == 1

        { 'id' => 'cot-2' }
      end)

      # Act
      described_class.new.perform(run.id, 0)
      intencao_apos_timeout = run.reload.handle
      described_class.new.perform(run.id, 1)

      # Assert
      expect(intencao_apos_timeout).to eq(intencoes => 1)
      expect(chamadas).to eq(2)
      expect(run.reload.handle).to include(submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true)
      expect(runs.possivelmente_duplicadas).to eq([run])
    end

    it 'e na terceira intencao para, sem chamar o portal, dizendo que nao ha confirmacao' do
      run = execucao
      chamadas = 0
      erro = incerto.new(:unavailable)
      register_async_tool(ferramenta_com_start do
        chamadas += 1
        raise erro
      end)

      described_class.new.perform(run.id, 0)
      described_class.new.perform(run.id, 1)
      described_class.new.perform(run.id, 2)

      expect(chamadas).to eq(2)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'envio_incerto')
      expect(run.handle).to eq(intencoes => 2, duplicada => true)
      expect(bot_contents).to eq(['não consegui confirmar o envio'])
    end

    it 'quando o prazo estoura com intencao sem numero, marca e diz que nao ha confirmacao' do
      # Arrange — morreu com a intenção anotada; a passada seguinte chega depois do prazo
      run = execucao(handle: { intencoes => 1 })
      run.update!(expires_at: 1.minute.ago)
      register_async_tool(build_async_tool)

      # Act
      described_class.new.perform(run.id, 1)

      # Assert
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(bot_contents).to eq(['não consegui confirmar o envio'])
    end
  end

  describe 'no desligamento' do
    it 'a intencao fica e o sinal sobe: Sidekiq::Shutdown nao e StandardError' do
      run = execucao
      register_async_tool(build_async_tool(start_error: Sidekiq::Shutdown))

      expect { described_class.new.perform(run.id, 0) }.to raise_error(Sidekiq::Shutdown)

      expect(run.reload.handle).to eq(intencoes => 1)
      expect(run.status).to eq('running')
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe 'a linha mudou de dono no meio da passada' do
    it 'pedido novo entre o perform e o start: o portal NAO e chamado para a execucao morta' do
      # Arrange — o cliente corrige o dado enquanto o job monta a ferramenta (depois do `running?`)
      run = execucao
      chamadas = 0
      tool = register_async_tool(ferramenta_com_start do
        chamadas += 1
        { 'id' => 'cot-X' }
      end)
      allow(tool).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        abrir # supersede a anterior
        original.call(*args, **kwargs)
      end

      # Act
      described_class.new.perform(run.id, 0)

      # Assert
      expect(chamadas).to eq(0)
      expect(run.reload).to have_attributes(status: 'superseded', handle: {})
      expect(described_class).not_to have_been_enqueued
    end

    it 'outro processo anotou a intencao seguinte durante o start: o numero deste nao sobrescreve a marca' do
      # Arrange — o job re-enfileirado (processo B) passa na frente enquanto A está no `start`
      run = execucao
      linha = runs
      marcas_de_b = { intencoes => 2, duplicada => true }
      register_async_tool(ferramenta_com_start do
        linha.find(run.id).merge_handle!(marcas_de_b)
        { 'id' => 'cot-A' }
      end)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — cot-A fica sem registro, mas a marca de B (que sabe que pode haver duas) permanece
      expect(run.reload.handle).to eq(marcas_de_b)
      expect(run.status).to eq('running')
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(described_class).not_to have_been_enqueued
    end

    it 'outro processo anotou durante um start que falhou: esta passada para, sem voltar a intencao dele' do
      run = execucao
      linha = runs
      marcas_de_b = { intencoes => 2, duplicada => true }
      register_async_tool(ferramenta_com_start do
        linha.find(run.id).merge_handle!(marcas_de_b)
        raise 'login caiu'
      end)

      described_class.new.perform(run.id, 0)

      expect(run.reload.handle).to eq(marcas_de_b)
      expect(run.status).to eq('running')
      expect(described_class).not_to have_been_enqueued
    end

    it 'A registrou o numero antes da segunda anotacao de B: B para, sem portal, e o numero fica' do
      # Arrange — B leu "intenção 1 sem número"; A registra cot-A enquanto B monta a ferramenta
      run = execucao(handle: { intencoes => 1 })
      chamadas = 0
      linha = runs
      registro_de_a = { submetido => true, 'id' => 'cot-A' }
      tool = register_async_tool(ferramenta_com_start do
        chamadas += 1
        { 'id' => 'cot-B' }
      end)
      allow(tool).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        linha.find(run.id).record_attempt!(handle: registro_de_a)
        original.call(*args, **kwargs)
      end

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — a posse acabou quando o número entrou: B não anota 2, não chama o portal, não reagenda
      expect(chamadas).to eq(0)
      expect(run.reload.handle).to eq(intencoes => 1, submetido => true, 'id' => 'cot-A')
      expect(run.status).to eq('running')
      expect(runs.possivelmente_duplicadas).to be_empty
      expect(described_class).not_to have_been_enqueued
    end

    it 'intencao anotada entre a marcacao do desfecho e o finish: o desfecho marca mesmo assim' do
      # Arrange — A chega ao desfecho com intenção zero (nada a marcar); B anota 0→1 enquanto A publica
      run = execucao
      run.update!(expires_at: 1.minute.ago)
      linha = runs
      register_async_tool(build_async_tool)
      publicador = Autonomia::Agents::Tools::AsyncPublisher
      allow(publicador).to receive(:new).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap do |instancia|
          allow(instancia).to receive(:publish).and_wrap_original do |publicar, *args|
            linha.find(run.id).merge_handle!({ intencoes => 1 }, intencao: 0)
            publicar.call(*args)
          end
        end
      end

      # Act
      described_class.new.perform(run.id, 1)

      # Assert — o `finish!` marca no mesmo comando que encerra; a anotação seguinte perde pelo status
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(run.handle).to eq(intencoes => 1, duplicada => true)
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(run.merge_handle!({ intencoes => 2 }, intencao: 1)).to be(false)
    end

    it 'objeto velho no desfecho: nao marca nem apaga o numero que outro processo registrou' do
      # Arrange — B chega ao desfecho (prazo) com a leitura "intenção 1 sem número"; A registra antes
      run = execucao(handle: { intencoes => 1 })
      run.update!(expires_at: 1.minute.ago)
      linha = runs
      registro_de_a = { submetido => true, 'id' => 'cot-A' }
      tool = register_async_tool(build_async_tool)
      allow(Autonomia::Agents::Tools::Registry).to receive(:find) do |slug|
        linha.find(run.id).record_attempt!(handle: registro_de_a)
        slug.to_s == tool.slug ? tool : nil
      end

      # Act
      described_class.new.perform(run.id, 1)

      # Assert — o número fica, a marca não entra, e a frase é a de falha (o banco diz que há número)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(run.handle).to eq(intencoes => 1, submetido => true, 'id' => 'cot-A')
      expect(runs.possivelmente_duplicadas).to be_empty
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end
  end

  describe 'as marcas sobrevivem' do
    it 'a consulta seguinte preserva intencoes e a marca de duplicata' do
      # Arrange — submetida como repetição, agora em consulta
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true })
      register_async_tool(build_async_tool(poll: progress.running(handle: { 'id' => 'cot-2', 'etapa' => 2 })))

      # Act
      described_class.new.perform(run.id, 1)

      # Assert — a ferramenta devolveu um handle novo SEM as nossas marcas, e elas voltaram
      expect(run.reload.handle).to include(submetido => true, 'etapa' => 2, intencoes => 2, duplicada => true)
    end

    it 'a ferramenta nunca ve as marcas: nem na consulta, nem no fechamento' do
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true,
                               Autonomia::Agents::ToolRun::PEDIDO => 'abc' })
      visto = []
      tool = build_async_tool(poll: progress.running)
      tool.define_method(:poll) do |handle:, **|
        visto << handle
        progress.running
      end
      tool.define_method(:closing_deliveries) do |handle|
        visto << handle
        []
      end
      register_async_tool(tool)

      described_class.new.perform(run.id, 1)
      run.record_delivery!
      run.update!(expires_at: 1.minute.ago)
      described_class.new.perform(run.id, 2)

      expect(visto).to eq([{ 'id' => 'cot-2' }, { 'id' => 'cot-2' }])
      expect(run.reload.status).to eq('failed')
    end
  end

  describe 'o encerramento' do
    it 'e adquirido no banco: dois processos com leitura velha nao geram dois comparativos' do
      # Arrange — preço entregue, prazo vencido; outro processo fecha enquanto este ainda lê "aberto"
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 1 })
      run.record_delivery!
      run.update!(expires_at: 1.minute.ago)
      fechamentos = 0
      linha = runs
      tool = build_async_tool
      tool.define_method(:closing_deliveries) do |_handle|
        fechamentos += 1
        ['comparativo']
      end
      register_async_tool(tool)
      allow(Autonomia::Agents::Tools::Registry).to receive(:find) do |slug|
        linha.find(run.id).merge_handle!({ described_class::CLOSED_KEY => true })
        slug.to_s == tool.slug ? tool : nil
      end

      # Act
      described_class.new.perform(run.id, 1)

      # Assert — quem perdeu a aquisição não gera comparativo nem publica
      expect(fechamentos).to eq(0)
      expect(bot_contents).to be_empty
      expect(run.reload.status).to eq('failed')
    end
  end

  describe 'o varredor' do
    it 'marca como possivelmente duplicada a execucao abandonada com intencao sem numero, e diz que nao ha confirmacao' do
      # Arrange — morreu com a intenção anotada, e ninguém voltou
      run = execucao(handle: { intencoes => 1 })
      run.update!(expires_at: 10.minutes.ago)
      register_async_tool(build_async_tool)

      # Act
      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      # Assert
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(bot_contents).to eq(['não consegui confirmar o envio'])
    end

    it 'nao marca a abandonada que nem chegou a anotar intencao' do
      run = execucao
      run.update!(expires_at: 10.minutes.ago)
      register_async_tool(build_async_tool)

      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      expect(runs.possivelmente_duplicadas).to be_empty
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end

    it 'recarrega antes de decidir: preco entregue enquanto ele varria fica sem "nao consegui"' do
      # Arrange — a linha veio da consulta sem entrega; um poll entrega um preço antes de o varredor chegar nela
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 1 })
      run.update!(expires_at: 10.minutes.ago)
      linha = runs
      tool = register_async_tool(build_async_tool)
      allow(Autonomia::Agents::Tools::Registry).to receive(:find) do |slug|
        linha.find(run.id).record_delivery!
        slug.to_s == tool.slug ? tool : nil
      end

      # Act
      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      # Assert
      expect(run.reload).to have_attributes(status: 'failed', delivered_count: 1)
      expect(bot_contents).to be_empty
    end

    it 'nao marca a abandonada que tem numero: a cotacao esta registrada' do
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 1 })
      run.update!(expires_at: 10.minutes.ago)
      register_async_tool(build_async_tool)

      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      expect(run.reload.status).to eq('failed')
      expect(runs.possivelmente_duplicadas).to be_empty
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
    end
  end
end
