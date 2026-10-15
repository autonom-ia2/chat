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
      incoming('mais uma')

      recebidos = eventos { described_class.perform_now(conversation.id, primeira.id) }

      expect(recebidos).to be_empty
      expect(Crm::Subjects::Marco.decidido_ate(conversation.id)).to be_nil
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
  end
end
