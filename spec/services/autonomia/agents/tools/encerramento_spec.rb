require 'rails_helper'

# O ENCERRAMENTO, PASSO A PASSO (entrega 8; o desfecho virou EVENTO na PR C).
#
# Ele é a ÚLTIMA coisa que acontece numa execução que acabou sem fechar, e a marca `closed` que ele
# adquire no primeiro passo impede que o TRABALHO se repita. O desfecho não é mais frase publicada: é o
# evento que ele dispara (`Tools::Evento`), e quem fala é a Lia. As propriedades que este arquivo trava:
#
#   - CADA PASSO CAI SOZINHO. O passo que consulta o banco (e, na cotação, o portal) levantando não cala o
#     desfecho: o evento sai de qualquer jeito.
#   - O DESFECHO SAI UMA VEZ. O slot do evento é adquirido no banco: a passada seguinte (retry, varredor)
#     não dispara outro, e não contradiz o primeiro.
#   - UMA ENTREGA NÃO DERRUBA AS OUTRAS, e a que o publicador recusa não conta.
#   - O DESFECHO COM RESULTADO SÓ É AFIRMADO QUANDO É VERDADE: são as perguntas à ferramenta (houve resultado?
#     sobrou algo?), e o contador sozinho não basta.
#   - NENHUMA FRASE AO CLIENTE SAI DAQUI: só arquivos, e o evento.
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
  let(:primeiro) { arquivo_de_teste('https://arquivos.exemplo.test/primeiro.pdf', nome: 'Primeiro.pdf') }
  let(:segundo) { arquivo_de_teste('https://arquivos.exemplo.test/segundo.pdf', nome: 'Segundo.pdf') }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    stub_arquivo('https://arquivos.exemplo.test/primeiro.pdf')
    stub_arquivo('https://arquivos.exemplo.test/segundo.pdf')
  end

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

  # Publicação FORÇADA, como a do varredor.
  def encerrar(run, tool, trabalho_novo: true, &publicador)
    register_async_tool(tool)
    publicador ||= ->(entrega) { Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega) }
    described_class.new(run: run, native: tool, trabalho_novo: trabalho_novo, &publicador).encerrar
  end

  # O que chegou à conversa: os nomes dos arquivos (a entrega de arquivo sai sem texto).
  def arquivos_na_conversa
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).flat_map { |m| m.attachments.map { |a| a.file.filename.to_s } }
  end

  def textos_na_conversa
    conversation.messages.reload.where(sender_type: 'AgentBot').filter_map { |m| m.content.presence }
  end

  describe 'cada passo cai sozinho, e o desfecho é a última coisa' do
    it 'a ferramenta que levanta ao montar as entregas nao cala o desfecho' do
      run = execucao
      tool = build_async_tool(closing: -> { raise ActiveRecord::StatementInvalid, 'banco fora' })

      entregou = encerrar(run, tool)

      expect(entregou).to be(false)
      expect(eventos_disparados(run)).to eq(['falhou'])
      expect(textos_na_conversa).to be_empty
    end

    # UMA ENTREGA NÃO DERRUBA AS OUTRAS, NEM APAGA O QUE JÁ SAIU (Codex): a exceção na SEGUNDA entrega não faz o
    # passo devolver `false`, e o desfecho é o de quem recebeu algo, não a falha.
    it 'a entrega que levanta nao apaga a que ja foi publicada, nem vira falha' do
      run = execucao
      tool = build_async_tool(closing: [primeiro, segundo], resultado: true, resta: true)
      publicador = lambda do |entrega|
        raise 'enfileirar a adiada falhou' if entrega == segundo

        Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
      end

      entregou = encerrar(run, tool, &publicador)

      expect(entregou).to be(true)
      expect(arquivos_na_conversa).to eq(['Primeiro.pdf'])
      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'publica todas as entregas do encerramento, e nao para na primeira' do
      run = execucao
      tool = build_async_tool(closing: [primeiro, segundo], resultado: true, resta: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(arquivos_na_conversa).to eq(['Primeiro.pdf', 'Segundo.pdf'])
      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'a entrega que levanta nao impede a seguinte' do
      run = execucao
      tool = build_async_tool(closing: [primeiro, segundo], resultado: true, resta: true)
      publicador = lambda do |entrega|
        raise 'enfileirar a adiada falhou' if entrega == primeiro

        Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
      end

      encerrar(run, tool, &publicador)

      expect(arquivos_na_conversa).to eq(['Segundo.pdf'])
    end

    # A MARCA IMPEDE O TRABALHO DUAS VEZES, E O SLOT IMPEDE O DESFECHO DUAS VEZES.
    it 'a segunda passada na mesma linha nao dispara outro desfecho' do
      run = execucao
      tool = build_async_tool

      encerrar(run, tool)
      de_novo = encerrar(run.reload, tool)

      expect(de_novo).to be(false)
      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    # A PASSADA SEGUINTE CONSERTA A PRIMEIRA QUE MORREU NO MEIO: marca posta e desfecho ausente, ela dispara o
    # desfecho e não refaz o trabalho.
    it 'marca posta e desfecho ausente: a passada seguinte fecha, e nao refaz o trabalho' do
      run = execucao
      chamadas = 0
      tool = build_async_tool
      tool.define_method(:closing_deliveries) do |_handle, **|
        chamadas += 1
        []
      end
      run.merge_handle!({ described_class::CLOSED_KEY => true })

      encerrar(run.reload, tool)

      expect(chamadas).to eq(0)
      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    # E A SEGUNDA PASSADA NÃO CONTRADIZ A PRIMEIRA: ela não refaz as entregas, leria `entregou` como falso e
    # escolheria outro tipo — o slot já está tomado.
    it 'a passada seguinte nao contradiz o desfecho que ja saiu' do
      run = execucao
      tool = build_async_tool(closing: [primeiro], resultado: false, resta: true)

      encerrar(run, tool)
      encerrar(run.reload, tool)

      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'a entrega recusada pelo publicador nao conta, e o desfecho e a falha' do
      run = execucao
      tool = build_async_tool(closing: [primeiro])
      publicador = ->(_entrega) { Autonomia::Agents::Tools::AsyncPublisher::Result.new(status: :blocked) }

      entregou = encerrar(run, tool, &publicador)

      expect(entregou).to be(false)
      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    it 'nao levanta quando tudo falha ao mesmo tempo' do
      run = execucao
      tool = build_async_tool(closing: -> { raise 'entregas' })
      tool.define_method(:resultado_entregue?) { |_handle| raise 'fecho' }
      allow(Autonomia::Agents::Operate::EventoJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

      expect { encerrar(run, tool) }.not_to raise_error
    end

    # O EVENTO QUE NÃO ENTRA NA FILA DEVOLVE O SLOT: a passada seguinte (o varredor) ainda consegue disparar.
    it 'a fila fora devolve o slot, e a passada seguinte dispara' do
      run = execucao
      tool = build_async_tool
      allow(Autonomia::Agents::Operate::EventoJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      encerrar(run, tool)
      expect(run.reload.handle).not_to have_key(Autonomia::Agents::Tools::Evento::FECHO_KEY)

      allow(Autonomia::Agents::Operate::EventoJob).to receive(:perform_later).and_call_original
      encerrar(run.reload, tool)

      expect(eventos_disparados(run)).to eq(['falhou'])
    end
  end

  describe 'o desfecho com resultado só é afirmado quando é verdade' do
    it 'contador positivo sem resultado nao dispara desfecho' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resta: true))

      expect(eventos_disparados(run)).to be_empty
    end

    # RESULTADO SEM SOBRA: a cotação cujo portal já tinha fechado e cujo comparativo já tinha saído. Desde a PR
    # C o comparativo sai sem legenda, e o desfecho é a conclusão.
    it 'resultado sem sobra conclui' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resultado: true))

      expect(eventos_disparados(run)).to eq(['concluida'])
    end

    it 'com resultado E sobra, o desfecho e o do prazo' do
      run = execucao(entregas: 1)

      encerrar(run, build_async_tool(resultado: true, resta: true))

      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'sem nada entregue, a falha' do
      run = execucao

      encerrar(run, build_async_tool(resta: true))

      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    it 'com resultado confirmado e contador zero, o desfecho de quem tem resultado' do
      run = execucao

      encerrar(run, build_async_tool(resultado: true, resta: true))

      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'com resultado guardado que nao chegou, os valores guardados' do
      run = execucao

      encerrar(run, build_async_tool(a_pedir: true))

      expect(eventos_disparados(run)).to eq(['valores_guardados'])
    end

    it 'a entrega aceita do encerramento nao sai com os valores guardados' do
      run = execucao
      tool = build_async_tool(closing: [primeiro], a_pedir: true, resta: true)

      encerrar(run, tool)

      expect(arquivos_na_conversa).to eq(['Primeiro.pdf'])
      expect(eventos_disparados(run)).to eq(['encerrada_por_prazo'])
    end

    it 'sem nada entregue e com envio incerto, a incerteza' do
      run = execucao(handle: { Autonomia::Agents::ToolRun::INTENCOES => 1 })

      encerrar(run, build_async_tool)

      expect(eventos_disparados(run)).to eq(['incerta'])
    end

    # A entrega DO ENCERRAMENTO tira do ramo da falha; sem sobra, é a conclusão (o arquivo saiu sem texto, e a
    # Lia fala depois dele).
    it 'a entrega do proprio encerramento, sem sobra, conclui' do
      run = execucao
      tool = build_async_tool(closing: [primeiro], resultado: true)

      entregou = encerrar(run, tool)

      expect(entregou).to be(true)
      expect(arquivos_na_conversa).to eq(['Primeiro.pdf'])
      expect(eventos_disparados(run)).to eq(['concluida'])
    end

    # SEM AGENTE não há ferramenta a quem perguntar: nada de resultado afirmado, e a falha continua saindo.
    it 'sem agente, nenhum resultado e afirmado, e a falha continua saindo' do
      com_entrega = execucao(entregas: 1)
      allow(com_entrega).to receive(:agent).and_return(nil)
      encerrar(com_entrega, build_async_tool(resultado: true, resta: true))

      outra_conversa = create(:conversation, account: account, inbox: inbox)
      sem_entrega = Autonomia::Agents::ToolRun.find(execucao.id)
      sem_entrega.update_columns(conversation_id: outra_conversa.id) # rubocop:disable Rails/SkipsModelValidations
      allow(sem_entrega).to receive(:agent).and_return(nil)
      encerrar(sem_entrega, build_async_tool(resultado: true, resta: true))

      expect(eventos_disparados(com_entrega)).to be_empty
      expect(eventos_disparados(sem_entrega)).to eq(['falhou'])
    end
  end

  # O DESFECHO DE QUEM TERMINOU (`done`): só o evento.
  describe 'a conclusão de quem terminou (done)' do
    def concluir(run, tool, evento = nil)
      register_async_tool(tool)
      publicador = ->(entrega) { Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega) }
      described_class.new(run: run, native: tool, &publicador).concluir(evento)
    end

    # DESDE A PR C, QUEM TERMINOU COM O COMPARATIVO NA MÃO RECEBE O EVENTO DE CONCLUSÃO: o PDF sai sem legenda, e
    # a Lia é quem fala depois dele.
    it 'com resultado confirmado pela ferramenta, conclui' do
      run = execucao(entregas: 1)

      concluir(run, build_async_tool(resultado: true, resta: true))

      expect(eventos_disparados(run)).to eq(['concluida'])
    end

    it 'com resultado guardado que nao chegou, os valores guardados' do
      run = execucao

      concluir(run, build_async_tool(a_pedir: true))

      expect(eventos_disparados(run)).to eq(['valores_guardados'])
    end

    it 'com resultado confirmado e contador zero, conclui, e nao falha' do
      run = execucao

      concluir(run, build_async_tool(resultado: true))

      expect(eventos_disparados(run)).to eq(['concluida'])
    end

    it 'sem nada aceito, a falha' do
      run = execucao

      concluir(run, build_async_tool)

      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    it 'com entrega aceita que nao e resultado, nenhum evento' do
      run = execucao(entregas: 1)

      concluir(run, build_async_tool(resultado: false))

      expect(eventos_disparados(run)).to be_empty
    end

    # O DESFECHO QUE A CONSULTA JÁ TROUXE (a recusa do envio) tem precedência sobre a escolha pelo estado.
    it 'o evento que a consulta trouxe tem precedencia' do
      run = execucao

      concluir(run, build_async_tool(a_pedir: true), 'falta_dado')

      expect(eventos_disparados(run)).to eq(['falta_dado'])
    end

    it 'duas conclusoes na mesma linha disparam um desfecho so' do
      run = execucao
      tool = build_async_tool

      concluir(run, tool)
      concluir(run.reload, tool)

      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    it 'deixa subir o que a ferramenta levanta, e nao dispara nada' do
      run = execucao(entregas: 1)
      tool = build_async_tool
      tool.define_method(:resultado_entregue?) { |_handle| raise ActiveRecord::StatementInvalid, 'banco fora' }

      expect { concluir(run, tool) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(eventos_disparados(run)).to be_empty
    end

    # E A FILA FORA SOBE TAMBÉM, com o slot devolvido: o motor tenta a passada de novo e o evento sai nela.
    it 'deixa subir a fila fora, com o slot devolvido' do
      run = execucao
      allow(Autonomia::Agents::Operate::EventoJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

      expect { concluir(run, build_async_tool) }.to raise_error(Redis::CannotConnectError)
      expect(run.reload.handle).not_to have_key(Autonomia::Agents::Tools::Evento::FECHO_KEY)
    end
  end

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
