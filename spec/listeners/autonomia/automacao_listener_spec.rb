require 'rails_helper'

# A escuta da Automação livre (#2414 F3, #2459): gatilhos começam, mudança acorda o "esperar até".
RSpec.describe Autonomia::AutomacaoListener, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before { ligar_motor(account) }

  after { Current.reset }

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def resolvida = automacao_ligada(account, admin, [esperar_passo('p1')])

  describe 'gatilhos' do
    it 'começa as automações ligadas do gatilho, e só elas', :aggregate_failures do
      do_gatilho = resolvida
      outra = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'conversa.criada' })
      desligada = resolvida.tap { |definicao| definicao.update!(ativa: false) }

      listener.conversation_resolved(evento('conversation.resolved', conversation: conversa))

      expect(execucoes.pluck(:automacao_id)).to eq([do_gatilho.id])
      expect(execucoes.first.chave_gatilho).to eq('conversa.resolvida')
      expect([outra, desligada].map { |definicao| execucoes.exists?(automacao: definicao) }).to eq([false, false])
    end

    # message.created é o evento mais frequente da plataforma: sem o motor, nenhum dos quatro toca as tabelas da
    # automação, e a mensagem nem carrega a conversa.
    it 'conta sem o motor não consulta automação nenhuma, em nenhum dos eventos', :aggregate_failures do
      resolvida
      mensagem = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming)
      account.disable_features!('automacao_motor')

      consultas = []
      contar = ->(*, dados) { consultas << dados[:sql] }
      ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
        listener.conversation_resolved(evento('conversation.resolved', conversation: Conversation.find(conversa.id)))
        listener.conversation_updated(evento('conversation.updated', conversation: Conversation.find(conversa.id)))
        listener.contact_updated(evento('contact.updated', contact: Contact.find(conversa.contact_id)))
        listener.message_created(evento('message.created', message: Message.find(mensagem.id)))
      end

      expect(consultas.select { |sql| sql.include?('autonomia_automacao') }).to be_empty
      expect(consultas.count { |sql| sql.include?('FROM "conversations"') }).to eq(2)
      expect(execucoes.count).to eq(0)
    end

    it 'mensagem criada começa "mensagem.criada"; atividade da plataforma não', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada' })

      atividade = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :activity)
      listener.message_created(evento('message.created', message: atividade))
      expect(execucoes.count).to eq(0)

      recebida = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming)
      listener.message_created(evento('message.created', message: recebida))
      expect(execucoes.where(automacao: definicao).count).to eq(1)
    end

    it 'o filtro "só recebida" ignora a nota privada e a resposta do atendente', :aggregate_failures do
      so_recebida = { 'campo' => { '$valor' => 'mensagem.tipo' }, 'op' => 'igual', 'valor' => 'recebida' }
      definicao = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada', 'filtros' => [so_recebida] })
      mensagem = lambda do |tipo, privada = false|
        create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: tipo, private: privada)
      end

      listener.message_created(evento('message.created', message: mensagem.call(:outgoing, true)))
      listener.message_created(evento('message.created', message: mensagem.call(:outgoing)))
      expect(execucoes.count).to eq(0)

      listener.message_created(evento('message.created', message: mensagem.call(:incoming)))
      expect(execucoes.where(automacao: definicao).count).to eq(1)
    end

    # A marca por evento (#2488 prometeu, PR-C entrega): o EventDispatcherJob repete o evento, e a repetição não pode
    # responder de novo ao cliente, nem depois que a primeira execução fechou.
    it 'o mesmo evento entregue 2x, com a 1ª execução já fechada, gera 1 execução e 1 mensagem; outro evento gera outra', :aggregate_failures do
      ligar_mensagens(account)
      definicao = automacao_ligada(account, admin, [mensagem_passo('p1', 'Recebemos.')], gatilho: { 'tipo' => 'mensagem.criada' })
      entregar = lambda do |mensagem|
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
      end
      primeira = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming)
      respostas = -> { conversa.messages.outgoing.where(private: false).count }

      entregar.call(primeira)
      expect([execucoes.where(automacao: definicao).pluck(:estado, :evento), respostas.call]).to eq([[['concluida', "mensagem:#{primeira.id}"]], 1])

      entregar.call(Message.find(primeira.id))
      expect([execucoes.where(automacao: definicao).count, respostas.call]).to eq([1, 1])

      entregar.call(create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming))
      expect([execucoes.where(automacao: definicao).count, respostas.call]).to eq([2, 2])
    end

    it 'uma automação que quebra não impede as outras' do
      quebra = resolvida
      segue = resolvida
      allow(Autonomia::Automacao::Partida).to receive(:new).and_wrap_original do |original, **argumentos|
        raise ActiveRecord::StatementInvalid, 'teste' if argumentos[:definicao] == quebra

        original.call(**argumentos)
      end

      listener.conversation_resolved(evento('conversation.resolved', conversation: conversa))

      expect(execucoes.pluck(:automacao_id)).to eq([segue.id])
    end

    it 'de ponta a ponta: resolver a conversa pela plataforma começa a automação' do
      definicao = resolvida

      perform_enqueued_jobs(only: EventDispatcherJob) { conversa.update!(status: :resolved) }

      expect(execucoes.where(automacao: definicao, alvo: conversa)).to exist
    end
  end

  describe '"esperar até" acordado pela mudança' do
    let(:urgente) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' } }
    let(:esperar_urgente) do
      { 'id' => 'e1', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => { 'valor' => 2, 'unidade' => 'dias' } }
    end

    def comecar_e_rodar(definicao)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload
    end

    it 'a conversa mudou e cumpriu a condição: segue na hora, sem esperar o prazo', :aggregate_failures do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_urgente, prioridade_passo('p2', 'low')]))
      expect(execucao.estado).to eq('esperando')

      conversa.update!(priority: :urgent)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        listener.conversation_updated(evento('conversation.updated', conversation: conversa))
      end

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'mudou mas a condição não fecha: volta a esperar com o mesmo prazo', :aggregate_failures do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_urgente, prioridade_passo('p2', 'low')]))
      prazo = execucao.due_at

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        listener.conversation_updated(evento('conversation.updated', conversation: conversa))
      end

      expect([execucao.reload.estado, execucao.due_at]).to eq(['esperando', prazo])
      expect(Autonomia::Automacao::Registro.where(execucao: execucao).count).to eq(1)
    end

    it 'a reserva da escuta que não começou (Redis fora) é reenfileirada pela varredura, apesar do prazo à frente', :aggregate_failures do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_urgente, prioridade_passo('p2', 'low')]))
      conversa.update!(priority: :urgent)
      allow(Autonomia::Automacao::AvancarJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      listener.conversation_updated(evento('conversation.updated', conversation: conversa))
      expect([execucao.reload.estado, execucao.due_at.future?]).to eq(['andando', true])
      allow(Autonomia::Automacao::AvancarJob).to receive(:perform_later).and_call_original

      travel(16.minutes) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
    end

    it 'um erro ao acordar uma execução não sobe para o evento' do
      comecar_e_rodar(automacao_ligada(account, admin, [esperar_urgente, prioridade_passo('p2', 'low')]))
      allow(Autonomia::Automacao::AvancarJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

      expect { listener.conversation_updated(evento('conversation.updated', conversation: conversa)) }.not_to raise_error
    end

    it 'o "esperar" de tempo não acorda com a mudança' do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_passo('p1'), prioridade_passo('p2')]))

      listener.conversation_updated(evento('conversation.updated', conversation: conversa))

      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'o contato mudou: acorda quem espera por um atributo dele' do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'placa')
      placa = { 'id' => 'e1', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 2, 'unidade' => 'dias' },
                'condicao' => { 'campo' => { '$valor' => 'contato.atributos.placa' }, 'op' => 'preenchido' } }
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [placa, prioridade_passo('p2', 'low')]))

      conversa.contact.update!(custom_attributes: { 'placa' => 'ABC1D23' })
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        listener.contact_updated(evento('contact.updated', contact: conversa.contact))
      end

      expect(execucao.reload.estado).to eq('concluida')
    end
  end

  # O evento de verdade, pelo despacho da plataforma, com a cadeia indo junto. Um job por vez, como no Sidekiq: o job
  # enfileirado dentro de outro só roda depois dele (o perform_enqueued_jobs com bloco os aninharia na mesma thread).
  describe 'pela plataforma, um job depois do outro' do
    let(:cadeia) { Autonomia::Automacao::Cadeia }

    def drenar
      drenados = [EventDispatcherJob, Autonomia::Automacao::AvancarJob]
      30.times do
        job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
        return unless job

        enqueued_jobs.delete(job)
        job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      end
      raise 'a fila não esvaziou em 30 jobs'
    end

    def status_passo(id, status)
      { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:id/toggle_status', 'descricao' => 'Mudar o status',
        'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'status' => status } }
    end

    def recusas(motivo) = have_received(:registrar_recusa).with(having_attributes(motivo: motivo), any_args)

    before { allow(cadeia).to receive(:registrar_recusa).and_call_original }

    it 'A (aberta: resolver) e B (resolvida: abrir) param no laço', :aggregate_failures do
      conversa.update!(status: :resolved)
      clear_enqueued_jobs
      resolve = automacao_ligada(account, admin, [status_passo('a1', 'resolved')], gatilho: { 'tipo' => 'conversa.aberta' })
      reabre = automacao_ligada(account, admin, [status_passo('b1', 'open')])

      conversa.update!(status: :open)
      drenar

      expect(execucoes.where(automacao: resolve).pluck(:estado)).to eq(['concluida'])
      expect(execucoes.where(automacao: reabre).pluck(:estado)).to eq(['concluida'])
      expect(cadeia).to recusas(:laco)
      expect(conversa.reload.status).to eq('open')
    end

    it 'a automação que resolve e reabre a mesma conversa roda uma vez: a volta é auto-disparo', :aggregate_failures do
      clear_enqueued_jobs
      definicao = automacao_ligada(account, admin, [status_passo('c1', 'resolved'), status_passo('c2', 'open')],
                                   gatilho: { 'tipo' => 'conversa.aberta' })
      conversa.update!(status: :resolved)
      conversa.update!(status: :open)
      drenar

      expect(execucoes.where(automacao: definicao).pluck(:estado)).to eq(['concluida'])
      expect(cadeia).to recusas(:auto_disparo)
      expect(conversa.reload.status).to eq('open')
    end

    # A resposta da própria automação é mensagem nova na conversa: o after_create_commit despacha com a cadeia da rodada,
    # e a Partida recusa o auto-disparo em vez de responder à própria resposta.
    it 'o passo mensagem não dispara a própria automação: 1 resposta e auto-disparo', :aggregate_failures do
      ligar_mensagens(account)
      definicao = automacao_ligada(account, admin, [mensagem_passo('p1', 'Oi')], gatilho: { 'tipo' => 'mensagem.criada' })
      clear_enqueued_jobs

      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming)
      drenar

      expect(execucoes.where(automacao: definicao).pluck(:estado)).to eq(['concluida'])
      expect(conversa.messages.outgoing.where(private: false).count).to eq(1)
      expect(cadeia).to recusas(:auto_disparo)
    end

    it 'uma rajada de mensagens abre uma execução só' do
      definicao = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada' })
      clear_enqueued_jobs

      3.times { create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming) }
      drenar

      expect(execucoes.where(automacao: definicao).count).to eq(1)
    end

    # Erro que sobe faz o EventDispatcherJob tentar de novo, e os outros listeners repetiriam webhooks e avisos.
    it 'erro na consulta ou no Motor.ligado? não sobe para o evento', :aggregate_failures do
      resolvida
      mensagem = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming)
      clear_enqueued_jobs
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).and_raise(ActiveRecord::StatementInvalid, 'valor do cliente')
      allow(ReportingEventListener.instance).to receive(:conversation_resolved)

      conversa.update!(status: :resolved)
      expect { drenar }.not_to raise_error
      expect(ReportingEventListener.instance).to have_received(:conversation_resolved).once

      allow(Autonomia::Automacao::Motor).to receive(:ligado?).and_raise(ActiveRecord::ConnectionNotEstablished)
      expect do
        listener.message_created(evento('message.created', message: mensagem))
        listener.conversation_updated(evento('conversation.updated', conversation: conversa))
        listener.contact_updated(evento('contact.updated', contact: conversa.contact))
      end.not_to raise_error
    end

    it 'o log do erro não leva a mensagem dele' do
      resolvida
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).and_raise(ActiveRecord::StatementInvalid, 'valor do cliente')
      allow(Rails.logger).to receive(:error)

      listener.conversation_resolved(evento('conversation.resolved', conversation: conversa))

      sem_a_mensagem = satisfy { |linha| linha.include?('ActiveRecord::StatementInvalid') && linha.exclude?('valor do cliente') }
      expect(Rails.logger).to have_received(:error).with(sem_a_mensagem)
    end
  end

  # A ação da rodada passa pelo caderno do Guia, um por thread: a rodada nunca pode rodar dentro de quem disparou.
  it 'a rodada nunca roda na thread do evento', :aggregate_failures do
    resolvida
    allow(Autonomia::Automacao::Executor).to receive(:rodar)

    listener.conversation_resolved(evento('conversation.resolved', conversation: conversa))

    expect(Autonomia::Automacao::Executor).not_to have_received(:rodar)
    expect(Autonomia::Automacao::AvancarJob).to have_been_enqueued
    expect(SyncDispatcher.new.listeners).not_to include(described_class.instance)
  end

  it 'está na lista do despacho assíncrono' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end
end
