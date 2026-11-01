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

  it 'está na lista do despacho assíncrono' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end
end
