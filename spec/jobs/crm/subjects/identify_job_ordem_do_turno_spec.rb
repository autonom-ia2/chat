require 'rails_helper'

# #1606 "Um turno, uma ordem": assunto → quem responde → resposta. A regra única ordem_do_turno?, a fila curta, o Sync
# em linha antes do marco, o marco em toda saída do IdentifyJob e o Canceler depois da decisão.
RSpec.describe Crm::Subjects::IdentifyJob do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  let(:identifier) { instance_double(Crm::Subjects::Identifier, perform: decisao) }
  let(:decisao) { instance_double(Crm::SubjectDecision, state: 'applied') }

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto)
    allow(Crm::Subjects::Identifier).to receive(:new).and_return(identifier)
    Redis::Alfred.delete(Crm::Subjects::Marco.chave(conversation.id))
  end

  def incoming(content = 'Oi')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def eventos(&)
    lista = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { lista << payload }, described_class::EVENTO, &)
    lista
  end

  describe 'Crm::Subjects.ordem_do_turno? (a regra única que o Agentes IA lê)' do
    it 'é verdadeira com a IA de assunto, a Fase 2 e responsável por funil na caixa' do
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(true)
    end

    it 'é verdadeira sem responsável na caixa quando há passagem em aberto' do
      Crm::InboxAiAgent.delete_all
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(false)

      Crm::Passagens.registrar!(conversation: conversation, de: porta, para: admin, pedida_por: nil, motivo: 'teste')
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(true)
    end

    it 'conta a passagem pessoa → robô em aberto (o robô atende uma conversa que veio de uma pessoa)' do
      Crm::InboxAiAgent.delete_all
      Crm::Passagens.registrar!(conversation: conversation, de: admin, para: porta, pedida_por: admin, motivo: 'devolucao')

      expect(Crm::Passagens.ultima_aberta(conversation).para).to have_attributes(tipo: :ia)
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(true)
    end

    it 'é falsa sem a IA de assunto na caixa, sem a IA do CRM ou sem a Fase 2 (linhas de responsável não contam)',
       :aggregate_failures do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :off)
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(false)

      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(false)

      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      Autonomia::Agents::Fase2.desligar!(account)
      expect(Crm::Subjects.ordem_do_turno?(conversation.reload)).to be(false)
    end
  end

  describe 'a fila do IdentifyJob' do
    def evento_da(mensagem)
      Events::Base.new('message.created', Time.zone.now, message: mensagem)
    end

    it 'na ordem do turno: fila high, espera de 3 s' do
      mensagem = incoming
      clear_enqueued_jobs

      Crm::ConversationObserverListener.instance.message_created(evento_da(mensagem))

      job = enqueued_jobs.find { |item| item['job_class'] == described_class.name }
      expect(job['queue_name']).to eq('high')
      expect(job['arguments']).to eq([conversation.id, mensagem.id, true])
      expect(job['scheduled_at'].to_time - Time.current).to be_within(1.5).of(Crm::Subjects::DEBOUNCE_ORDEM)
    end

    it 'fora dela (conta sem responsável nem passagem): fila low e 15 s, como hoje' do
      Crm::InboxAiAgent.delete_all
      mensagem = incoming
      clear_enqueued_jobs

      Crm::ConversationObserverListener.instance.message_created(evento_da(mensagem))

      job = enqueued_jobs.find { |item| item['job_class'] == described_class.name }
      expect(job['queue_name']).to eq('low')
      expect(job['scheduled_at'].to_time - Time.current).to be_within(1.5).of(Crm::Subjects::DEBOUNCE)
    end

    # #1642: a mensagem recuperada pelo WhatsApp Híbrido passa pelo mesmo Crm::Subjects.identificar_depois.
    def recuperar(mensagem)
      payload = { message_id: mensagem.id, conversation_id: conversation.id, account_id: account.id }
      ActiveSupport::Notifications.instrument('whatsapp_hybrid.message_recovered', payload)
    end

    it 'mensagem recuperada na ordem do turno: fila high, espera de 3 s' do
      mensagem = incoming
      clear_enqueued_jobs

      recuperar(mensagem)

      job = enqueued_jobs.sole
      expect(job).to include('job_class' => described_class.name, 'queue_name' => 'high')
      expect(job['scheduled_at'].to_time - Time.current).to be_within(1.5).of(Crm::Subjects::DEBOUNCE_ORDEM)
    end

    it 'mensagem recuperada fora da ordem do turno: fila low e 15 s, como hoje' do
      Crm::InboxAiAgent.delete_all
      mensagem = incoming
      clear_enqueued_jobs

      recuperar(mensagem)

      job = enqueued_jobs.sole
      expect(job).to include('job_class' => described_class.name, 'queue_name' => 'low')
      expect(job['scheduled_at'].to_time - Time.current).to be_within(1.5).of(Crm::Subjects::DEBOUNCE)
    end
  end

  describe 'o marco "assunto decidido"' do
    it 'só avança e expira em 10 minutos' do
      Crm::Subjects::Marco.gravar(conversation.id, 20)
      Crm::Subjects::Marco.gravar(conversation.id, 10)

      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to eq(20)
      expect(Crm::Subjects::Marco.decidido_ate?(conversation.id, 20)).to be(true)
      expect(Crm::Subjects::Marco.decidido_ate?(conversation.id, 21)).to be(false)
      ttl = Redis::Alfred.with { |conn| conn.ttl(Crm::Subjects::Marco.chave(conversation.id)) }
      expect(ttl).to be_within(5).of(600)
    end

    it 'é gravado depois de decidir, com o evento crm.subject.decided e o estado' do
      mensagem = incoming

      recebidos = eventos { described_class.perform_now(conversation.id, mensagem.id) }

      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to eq(mensagem.id)
      expect(recebidos.sole).to eq(conversation_id: conversation.id, message_id: mensagem.id, estado: 'applied')
    end

    it 'é gravado com o CRM desligado e com a mensagem sumida' do
      mensagem = incoming
      allow(Crm::Config).to receive(:enabled?).and_return(false)
      recebidos = eventos { described_class.perform_now(conversation.id, mensagem.id) }
      expect(recebidos.sole[:estado]).to eq('crm_desligado')

      allow(Crm::Config).to receive(:enabled?).and_return(true)
      recebidos = eventos { described_class.perform_now(conversation.id, mensagem.id + 1000) }
      expect(recebidos.sole[:estado]).to eq('mensagem_sumida')
      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to eq(mensagem.id + 1000)
    end

    it 'é gravado mesmo quando a decisão quebra, e a exceção segue' do
      mensagem = incoming
      allow(identifier).to receive(:perform).and_raise(ArgumentError)

      recebidos = eventos do
        expect { described_class.perform_now(conversation.id, mensagem.id) }.to raise_error(ArgumentError)
      end

      expect(recebidos.sole[:estado]).to eq('erro')
      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to eq(mensagem.id)
    end

    it 'NÃO é gravado quando chegou mensagem mais nova: o job dela grava' do
      primeira = incoming
      segunda = incoming('mais uma')

      recebidos = eventos { described_class.perform_now(conversation.id, primeira.id) }

      expect(recebidos).to be_empty
      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to be_nil

      described_class.perform_now(conversation.id, segunda.id)
      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to eq(segunda.id)
      expect(Crm::Subjects::Marco.decidido_ate?(conversation.id, primeira.id)).to be(true)
    end
  end

  describe 'o dono troca EM LINHA antes do marco' do
    # Pega o achado 1 da Agentes IA: marco visto com o Sync ainda na fila faria o dono antigo responder.
    it 'na ordem do turno, quando o marco sai o dono já é o responsável do funil novo' do
      mensagem = incoming
      allow(identifier).to receive(:perform) do
        create_card(pipeline: suporte)
        decisao
      end
      dono_no_marco = nil
      callback = ->(*, payload) { dono_no_marco = Conversation.find(payload[:conversation_id]).ai_assignee }

      ActiveSupport::Notifications.subscribed(callback, described_class::EVENTO) do
        described_class.perform_now(conversation.id, mensagem.id)
      end

      expect(dono_no_marco).to eq(espelho_area)
    end

    # Pega o achado do revisor: o aviso em tempo real quebra DEPOIS de aplicar o assunto; antes o Sync não rodava e o
    # marco saía com o dono antigo.
    it 'a decisão quebra depois de aplicar o assunto: o Sync roda antes do marco e a exceção segue para o retry' do
      mensagem = incoming
      allow(identifier).to receive(:perform) do
        create_card(pipeline: suporte)
        raise ActiveRecord::StatementInvalid, 'aviso quebrou'
      end
      dono_no_marco = nil
      callback = ->(*, payload) { dono_no_marco = Conversation.find(payload[:conversation_id]).ai_assignee }

      ActiveSupport::Notifications.subscribed(callback, described_class::EVENTO) do
        expect { described_class.perform_now(conversation.id, mensagem.id) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      expect(dono_no_marco).to eq(espelho_area)
    end

    # Redis fora de verdade: um cliente apontado para uma porta sem ninguém. A decisão sai, a falha vai para o log e o
    # rastreador, e o job levanta para o retry gravar o marco (a reserva única da decisão evita perguntar de novo).
    it 'sem Redis a decisão sai, a falha do marco fica registrada e o job levanta para o retry' do
      mensagem = incoming
      fora = Redis.new(url: 'redis://127.0.0.1:1/0', reconnect_attempts: 0, connect_timeout: 0.2)
      allow(Redis::Alfred).to receive(:with).and_yield(fora)
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
      saida = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(saida)

      begin
        expect { described_class.perform_now(conversation.id, mensagem.id) }.to raise_error(Redis::BaseConnectionError)
      ensure
        Rails.logger = original
      end

      expect(identifier).to have_received(:perform)
      expect(rastreador).to have_received(:capture_exception)
      expect(saida.string).to include("marco_nao_gravado conversa=#{conversation.id} mensagem=#{mensagem.id}")
    end

    it 'a regra do turno vem do enqueue: o Sync segue a fila escolhida, não a regra relida depois da espera' do
      mensagem = incoming
      allow(Crm::Subjects).to receive(:ordem_do_turno?).and_return(false)
      allow(Crm::Ai::ResponsibleAgentSync).to receive(:new).and_call_original

      described_class.perform_now(conversation.id, mensagem.id, true)
      expect(Crm::Ai::ResponsibleAgentSync).to have_received(:new).once

      described_class.perform_now(conversation.id, mensagem.id, false)
      expect(Crm::Ai::ResponsibleAgentSync).to have_received(:new).once
    end

    it 'fora da ordem do turno, o Sync não roda em linha (segue assíncrono, como hoje)' do
      Crm::InboxAiAgent.delete_all
      mensagem = incoming
      allow(Crm::Ai::ResponsibleAgentSync).to receive(:new).and_call_original

      described_class.perform_now(conversation.id, mensagem.id)

      expect(Crm::Ai::ResponsibleAgentSync).not_to have_received(:new)
    end
  end

  describe 'a cadência de follow-up para depois da decisão (corrida f)' do
    def cadencia_ativa(card)
      card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => true } } })
      account.crm_follow_ups.create!(card: card, conversation: conversation, title: 'Toque', due_at: 1.hour.from_now,
                                     timezone: 'UTC', automation_mode: :reminder_only, metadata: { 'source' => 'ai_followup' })
    end

    it 'o cliente falou de outro pedido: a cadência do card antigo continua' do
      antigo = create_card(pipeline: comercial, focused_at: 2.minutes.ago)
      toque = cadencia_ativa(antigo)
      mensagem = incoming('Na verdade quero suporte')
      allow(identifier).to receive(:perform) do
        create_card(pipeline: suporte)
        decisao
      end

      described_class.perform_now(conversation.id, mensagem.id)

      expect(toque.reload.status).to eq('pending')
    end

    it 'a decisão quebrou: a cadência do assunto em foco para do mesmo jeito' do
      card = create_card(pipeline: comercial)
      toque = cadencia_ativa(card)
      mensagem = incoming('Ainda tenho interesse')
      allow(identifier).to receive(:perform).and_raise(ArgumentError)

      expect { described_class.perform_now(conversation.id, mensagem.id) }.to raise_error(ArgumentError)
      expect(toque.reload.status).to eq('canceled')
    end

    it 'o cliente respondeu no mesmo assunto: a cadência para' do
      card = create_card(pipeline: comercial)
      toque = cadencia_ativa(card)
      mensagem = incoming('Ainda tenho interesse')

      described_class.perform_now(conversation.id, mensagem.id)

      expect(toque.reload.status).to eq('canceled')
    end

    it 'com a IA de assunto ligada, o CardSyncer não para a cadência antes da decisão; desligada, para como antes' do
      account.crm_pipeline_inboxes.find_by(pipeline: comercial).update!(auto_create_card: true)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      card = create_card(pipeline: comercial)
      toque = cadencia_ativa(card)
      mensagem = incoming('Na verdade quero suporte')

      Crm::Conversations::CardSyncer.new(conversation: conversation, message: mensagem).perform
      expect(toque.reload.status).to eq('pending')

      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :off)
      Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: mensagem).perform
      expect(toque.reload.status).to eq('canceled')
    end

    # Pega o achado do revisor: com a IA de assunto ligada mas fora da ordem do turno (sem área), o CardSyncer para a
    # cadência na hora, como sempre foi; só na ordem do turno quem para é o IdentifyJob.
    it 'IA de assunto ligada e fora da ordem do turno: o CardSyncer para a cadência na hora' do
      Crm::InboxAiAgent.delete_all
      account.crm_pipeline_inboxes.find_by(pipeline: comercial).update!(auto_create_card: true)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      card = create_card(pipeline: comercial)
      toque = cadencia_ativa(card)
      mensagem = incoming('Ainda tenho interesse')
      expect(Crm::Subjects.ligado?(conversation)).to be(true)
      expect(Crm::Subjects.ordem_do_turno?(conversation)).to be(false)

      Crm::Conversations::CardSyncer.new(conversation: conversation, message: mensagem).perform

      expect(toque.reload.status).to eq('canceled')
    end
  end
end
