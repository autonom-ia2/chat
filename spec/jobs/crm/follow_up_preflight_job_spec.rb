require 'rails_helper'

# Pré-voo (#1624) pelo caminho real: o varredor de 1 minuto enfileira, o job de um follow-up grava a marca e, no horário, o
# DueProcessor entrega pelo modelo planejado. As fronteiras são dublês: a IA (ResponsesClient) e a conferência na Meta.
RSpec.describe Crm::FollowUpPreflightJob do
  include CrmHybridHelpers
  include ActiveJob::TestHelper

  before do
    travel_to Time.utc(2026, 10, 16, 14)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::FollowUps::ServiceReminderScheduler).to receive(:wanted?).and_return(true)
  end

  let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:cobranca_vencimento, momento: :no_dia, com_valor: true) }
  let(:modelo) { pronto.corpo.deep_stringify_keys.merge('id' => '9', 'status' => 'APPROVED', 'language' => 'pt_BR') }
  let!(:scenario) { build_crm_hybrid_scenario(templates: [modelo], hybrid: false, last_inbound_ago: 30.hours.ago) }

  def agendar(para:, source: 'service_reminder', metadata: { 'kind' => 'payment_due', 'key' => 'payment_due:2026-10-16' })
    scenario[:card].update!(value_cents: 35_000, expected_close_at: Date.new(2026, 10, 16))
    create_crm_hybrid_follow_up(scenario, source: source, metadata: metadata).tap { |created| created.update!(due_at: para) }
  end

  describe 'o varredor' do
    it 'enfileira só o que vence nos próximos 10 minutos e ainda não tem a marca' do
      dentro = agendar(para: 6.minutes.from_now)
      agendar(para: 11.minutes.from_now)
      agendar(para: 1.minute.ago)

      expect { described_class.perform_now }.to have_enqueued_job(Crm::FollowUpPreflightRunJob).with(dentro.id).exactly(:once)
    end

    it 'não enfileira de novo depois da marca, nem follow-up de IA comum, nem lembrete só para a equipe, nem cancelado' do
      feito = agendar(para: 5.minutes.from_now)
      feito.update!(metadata: feito.metadata.merge('preflight' => { 'estado' => 'pronto', 'due_at' => Crm::FollowUps::Preflight.horario(feito) }))
      agendar(para: 5.minutes.from_now, source: 'ai_followup', metadata: {})
      agendar(para: 5.minutes.from_now).update!(automation_mode: :reminder_only)
      agendar(para: 5.minutes.from_now).update!(status: :canceled, canceled_at: Time.current)

      expect { described_class.perform_now }.not_to have_enqueued_job(Crm::FollowUpPreflightRunJob)
    end

    it 'com o CRM ou a IA desligados, não faz nada' do
      agendar(para: 5.minutes.from_now)
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

      expect { described_class.perform_now }.not_to have_enqueued_job(Crm::FollowUpPreflightRunJob)
    end

    it 'está no cron de minuto em minuto' do
      schedule = YAML.safe_load_file(Rails.root.join('config/schedule.yml'), aliases: true)

      expect(schedule['crm_follow_up_preflight_job']).to include('class' => 'Crm::FollowUpPreflightJob', 'cron' => '*/1 * * * *',
                                                                 'queue' => 'scheduled_jobs')
    end
  end

  describe 'do pré-voo ao envio, pelos jobs reais' do
    let(:checagem) { instance_double(Whatsapp::Templates::DispatchCheck) }

    before do
      verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: nil, template: modelo, details: { lookup_source: 'meta' })
      allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(checagem)
      allow(checagem).to receive(:call).and_return(verdict)
    end

    it 'grava a marca 10 min antes e, no horário, envia o modelo da cobrança com o registro, lendo a conversa uma vez' do
      follow_up = agendar(para: 6.minutes.from_now)
      seed_crm_hybrid_transcript(scenario)
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('closure_detected' => false))

      perform_enqueued_jobs { described_class.perform_now }

      marca = follow_up.reload.metadata['preflight']
      expect(marca).to include('estado' => 'pronto', 'tipo' => 'cobranca_no_dia')
      expect(marca['plano']).to include('caminho' => 'modelo', 'nome' => pronto.nome)
      expect(ai_calls).to be_empty

      travel_to Time.utc(2026, 10, 16, 14, 7)
      expect { Crm::FollowUps::DueProcessor.new.perform }.to change(Message, :count).by(1).and change(WhatsappOutOfWindowSend, :count).by(1)

      expect(follow_up.reload).to be_done
      expect(follow_up.metadata).to include('template_name' => pronto.nome, 'send_mode' => 'template')
      expect(WhatsappOutOfWindowSend.last).to have_attributes(crm_follow_up_id: follow_up.id, tipo: 'cobranca_no_dia')
    end

    it 'sem o pré-voo (job fora do ar), o envio funciona como antes: planeja sem criar e envia o que já está aprovado' do
      follow_up = agendar(para: 6.minutes.from_now)
      seed_crm_hybrid_transcript(scenario)
      stub_crm_hybrid_ai(crm_hybrid_ai_answer('closure_detected' => false))

      travel_to Time.utc(2026, 10, 16, 14, 7)
      expect { Crm::FollowUps::DueProcessor.new.perform }.to change(Message, :count).by(1)

      expect(follow_up.reload).to be_done
      expect(follow_up.metadata).not_to have_key('preflight')
    end
  end
end
