require 'rails_helper'

# Follow-up automático que não saiu por falha passageira da Meta vira aviso para a equipe (#1624, ponto (b) do #1734).
# Reagendar esse aviso tem de tentar o envio de novo: o modo original volta (guardado no `callback_original`, do servidor),
# e a descrição que o aviso trocou também. Falha que não é passageira, ou aviso que nunca foi automático, continua só aviso.
RSpec.describe Crm::FollowUps::CallbackFallback do
  include CrmHybridHelpers

  before do
    travel_to Time.utc(2026, 10, 17, 14)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:pipeline_callback_enabled?).and_return(true)
    allow(Crm::FollowUps::ServiceReminderScheduler).to receive(:wanted?).and_return(true)
    allow(Crm::FollowUps::Broadcaster).to receive(:broadcast_due)
  end

  let!(:scenario) { build_crm_hybrid_scenario(templates: [CrmHybridHelpers::APPROVED_TEMPLATE], hybrid: false, last_inbound_ago: 30.hours.ago) }
  let(:source) { 'ai_callback' }
  let!(:follow_up) { create_crm_hybrid_follow_up(scenario, source: source, metadata: { 'requested_at_text' => 'terça às 8h' }) }
  let(:motivo) { 'conferencia_sem_meta' }
  let(:future) { 2.hours.from_now }

  def runner_devolve_fallback(error)
    result = Crm::FollowUps::CallbackRunner::Result.new(status: :fallback, error: error)
    allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(instance_double(Crm::FollowUps::CallbackRunner, perform: result))
  end

  def vencer!
    runner_devolve_fallback(motivo)
    Crm::FollowUps::DueProcessor.new(now: Time.current).perform
    follow_up.reload
  end

  def reagendar!(user: scenario[:user], due_at: future)
    Crm::FollowUps::Rescheduler.new(follow_up: follow_up.reload, user: user, due_at: due_at).perform
    follow_up.reload
  end

  def aviso
    I18n.with_locale(scenario[:account].locale) { Crm::FollowUps::EnvioForaDaJanela.aviso(motivo) }
  end

  describe 'quando o envio cai para a equipe' do
    it 'guarda o modo e a descrição de antes, vira lembrete e explica o motivo para a equipe (retorno)' do
      follow_up.update!(description: 'ligar sobre o contrato')

      vencer!

      expect(follow_up).to be_overdue
      expect(follow_up).to be_reminder_only
      expect(follow_up.description).to eq(aviso)
      expect(follow_up.metadata).to include('callback_fallback' => motivo,
                                            'callback_original' => { 'automation_mode' => 'auto_send_message',
                                                                     'description' => 'ligar sobre o contrato' })
    end

    describe 'com lembrete de Atender (cobrança)' do
      let(:source) { Crm::FollowUps::ServiceReminderScheduler::SOURCE }

      it 'mantém a explicação do motivo e guarda o que havia' do
        vencer!

        expect(follow_up.description).to eq(aviso)
        expect(follow_up.metadata['callback_original']).to eq('automation_mode' => 'auto_send_message', 'description' => nil)
      end
    end

    it 'motivo que não é passageiro avisa a equipe e não pode ser desfeito ao reagendar' do
      runner_devolve_fallback('no_template')
      Crm::FollowUps::DueProcessor.new(now: Time.current).perform

      follow_up.reload
      expect(follow_up).to be_reminder_only
      expect(follow_up.metadata).to include('callback_fallback' => 'no_template')
      expect(described_class.restorable?(follow_up)).to be(false)
    end

    it 'follow-up só-lembrete que nunca guardou o original não é restaurável' do
      follow_up.update!(automation_mode: :reminder_only, status: :overdue, metadata: follow_up.metadata.merge('source' => 'manual'))

      expect(described_class.restorable?(follow_up.reload)).to be(false)
    end
  end

  describe 'reagendar o aviso' do
    it 'volta ao envio automático, devolve a descrição e limpa o aviso (motivo passageiro)' do
      follow_up.update!(description: 'ligar sobre o contrato')
      vencer!

      reagendar!

      expect(follow_up).to be_pending
      expect(follow_up).to be_auto_send_message
      expect(follow_up.description).to eq('ligar sobre o contrato')
      expect(follow_up.due_at.to_i).to eq(future.to_i)
      expect(follow_up.metadata).not_to include('callback_fallback', 'callback_original')
    end

    it 'devolve descrição vazia quando não havia nenhuma' do
      vencer!

      reagendar!

      expect(follow_up.description).to be_nil
    end

    it 'o novo horário tem de estar no futuro, como todo envio automático; nada muda' do
      vencer!

      expect { reagendar!(due_at: 1.hour.ago) }.to raise_error(Crm::FollowUps::Rescheduler::PastDueError)

      follow_up.reload
      expect(follow_up).to be_overdue
      expect(follow_up).to be_reminder_only
      expect(follow_up.metadata).to have_key('callback_original')
    end

    it 'motivo que não é passageiro: reagendar continua só lembrete' do
      runner_devolve_fallback('no_template')
      Crm::FollowUps::DueProcessor.new(now: Time.current).perform

      reagendar!

      expect(follow_up).to be_pending
      expect(follow_up).to be_reminder_only
    end

    it 'aviso já concluído pela equipe não volta a ser envio automático ao reagendar' do
      vencer!
      follow_up.update!(status: :done, completed_at: Time.current)

      reagendar!

      expect(follow_up).to be_done
      expect(follow_up).to be_reminder_only
    end

    it 'quem dispensou o aviso volta a ser avisado se o envio cair de novo' do
      vencer!
      Crm::FollowUps::ReminderDismisser.new(follow_up: follow_up, user: scenario[:user]).perform
      expect(Crm::FollowUps::ReminderDismisser.dismissed_for?(follow_up: follow_up.reload, user: scenario[:user])).to be(true)

      reagendar!
      expect(Crm::FollowUps::ReminderDismisser.dismissed_for?(follow_up: follow_up, user: scenario[:user])).to be(false)

      travel_to(follow_up.due_at + 1.minute)
      vencer!

      expect(follow_up).to be_overdue
      expect(Crm::FollowUps::ReminderDismisser.dismissed_for?(follow_up: follow_up, user: scenario[:user])).to be(false)
    end

    it 'já existe outro envio automático do mesmo tipo esperando no card: reagendar o aviso continua só lembrete' do
      vencer!
      create_crm_hybrid_follow_up(scenario, source: source).update!(due_at: 1.day.from_now)

      reagendar!

      expect(follow_up).to be_pending
      expect(follow_up).to be_reminder_only
    end

    it 'motivo passageiro sem o original guardado (metadata trocado pela API): reagendar não quebra nem vira envio automático' do
      vencer!
      follow_up.update!(metadata: follow_up.metadata.except(described_class::KEY))

      expect { reagendar! }.not_to raise_error

      expect(follow_up).to be_reminder_only
    end

    it 'lembrete que sempre foi só lembrete não vira envio automático ao reagendar' do
      follow_up.update!(automation_mode: :reminder_only, status: :overdue)

      reagendar!

      expect(follow_up).to be_pending
      expect(follow_up).to be_reminder_only
    end

    it 'no novo horário o envio é tentado de novo (e não só outro lembrete)' do
      vencer!
      reagendar!(due_at: 5.minutes.from_now)
      result = Crm::FollowUps::CallbackRunner::Result.new(status: :sent)
      runner = instance_double(Crm::FollowUps::CallbackRunner, perform: result)
      allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(runner)

      travel 10.minutes
      Crm::FollowUps::DueProcessor.new(now: Time.current).perform

      expect(runner).to have_received(:perform)
      expect(follow_up.reload).to be_done
    end
  end

  # #1855: "Passar tudo para amanhã" do calendário só move lembrete de uma pessoa. Um clique em lote nunca devolve envio
  # ao cliente; o reagendamento item a item (acima) continua tentando o envio de novo.
  describe 'reagendar em lote, só lembretes (reminders_only)' do
    def adiar_em_lote!(alvo = follow_up)
      Crm::FollowUps::Rescheduler.new(follow_up: alvo.reload, user: scenario[:user], due_at: future, reminders_only: true).perform
    end

    it 'aviso de envio que caiu por falha passageira fica de fora: não move e não volta a envio automático' do
      vencer!
      due_at = follow_up.due_at

      expect { adiar_em_lote! }.to raise_error(Crm::FollowUps::Rescheduler::NotAReminderError)

      follow_up.reload
      expect(follow_up).to be_overdue
      expect(follow_up).to be_reminder_only
      expect(follow_up.due_at.to_i).to eq(due_at.to_i)
      expect(follow_up.metadata).to include('callback_original', 'callback_fallback' => motivo)
    end

    it 'aviso de envio que caiu por motivo que não é passageiro também fica de fora' do
      runner_devolve_fallback('no_template')
      Crm::FollowUps::DueProcessor.new(now: Time.current).perform

      expect { adiar_em_lote! }.to raise_error(Crm::FollowUps::Rescheduler::NotAReminderError)
      expect(follow_up.reload).to be_overdue
    end

    it 'envio automático (mensagem marcada) fica de fora' do
      expect(follow_up).to be_auto_send_message

      expect { adiar_em_lote! }.to raise_error(Crm::FollowUps::Rescheduler::NotAReminderError)
    end

    it 'lembrete comum atrasado passa para o novo horário' do
      follow_up.update!(automation_mode: :reminder_only, status: :overdue)

      adiar_em_lote!

      follow_up.reload
      expect(follow_up).to be_pending
      expect(follow_up).to be_reminder_only
      expect(follow_up.due_at.to_i).to eq(future.to_i)
    end

    it 'lembrete que adia a conversa (snooze_conversation) passa para o novo horário' do
      follow_up.update!(automation_mode: :snooze_conversation, status: :overdue)

      adiar_em_lote!

      expect(follow_up.reload).to be_pending
      expect(follow_up).to be_snooze_conversation
      expect(follow_up.due_at.to_i).to eq(future.to_i)
    end
  end

  it 'o cliente não consegue forjar nem apagar a marca de volta pela API' do
    expect(Crm::FollowUps::MetadataSanitizer::SERVER_OWNED_KEYS).to include('callback_original')
  end
end
