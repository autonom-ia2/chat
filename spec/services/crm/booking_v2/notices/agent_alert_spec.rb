require 'rails_helper'

# Alerta ao responsável (#1291): a tarefa do CRM leva no `metadata` o que o cartão do painel precisa para dizer o que
# houve (aviso não saiu, de quem, de qual horário e por quê), e o aviso que não saiu chama uma vez por reunião.
RSpec.describe Crm::BookingV2::Notices::AgentAlert do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:meeting) { create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z')) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  def alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'source' = ?", described_class::SOURCE)
  end

  it 'aviso que não saiu vira tarefa-lembrete do responsável, marcada como alerta do agendamento com cliente, horário, tipo e motivo' do
    described_class.new(meeting, 'notice_failed', { kind: 'booked', reason: 'template_required' }).perform

    alert = alerts.sole
    expect(alert).to have_attributes(
      follow_up_type: 'task', automation_mode: 'reminder_only', status: 'pending', due_at: Time.current,
      assignee_id: world.host.id, card_id: world.card.id, contact_id: world.contact.id
    )
    expect(alert.metadata).to eq(
      'source' => 'booking_agent_alert', 'event' => 'notice_failed', 'meeting_id' => meeting.id,
      'contact_name' => 'Marcos Lima', 'starts_at' => '2026-10-20T13:00:00Z', 'kind' => 'booked', 'reason' => 'template_required'
    )
    expect(alert.title).to eq(
      'O aviso no WhatsApp para Marcos Lima não saiu. O horário de 20/10 às 10:00 continua marcado: fale com o cliente.'
    )
  end

  # #1562: a mensagem 2 que não saiu avisa uma vez POR AVISO ENVIADO (notice_id + message_id no metadata). Pega quem
  # deduplicasse pela reunião ou pelo tipo (o aviso remarcado reaproveita a linha e falharia de novo sem alerta) ou
  # não deduplicasse nada.
  it 'notice_stop_failed avisa uma vez por aviso enviado: o mesmo de novo não, o remarcado e outro aviso sim' do
    payload = ->(notice_id, message_id) { { kind: 'booked', reason: 'stop_part_failed', notice_id: notice_id, message_id: message_id } }
    described_class.new(meeting, 'notice_stop_failed', payload.call(10, 100)).perform
    described_class.new(meeting, 'notice_stop_failed', payload.call(10, 100)).perform
    described_class.new(meeting, 'notice_stop_failed', payload.call(10, 200)).perform
    described_class.new(meeting, 'notice_stop_failed', payload.call(11, 300)).perform

    expect(alerts.map { |alert| alert.metadata.values_at('notice_id', 'message_id') })
      .to contain_exactly(%w[10 100], %w[10 200], %w[11 300])
    expect(alerts.first.title).to start_with('O aviso no WhatsApp para Marcos Lima saiu, mas a mensagem com o botão "Parar avisos" não.')
  end

  it 'motivo que a atendente resolve entra no texto da tarefa (push e e-mail)' do
    described_class.new(meeting, 'notice_failed', { kind: 'booked', reason: 'no_whatsapp' }).perform

    expect(alerts.sole.title).to end_with('fale com o cliente. O número do cliente não tem WhatsApp.')
  end

  it 'chama uma vez por reunião, mesmo com outro aviso e outro motivo, e registra cada falha no card' do
    described_class.new(meeting, 'notice_failed', { kind: 'booked', reason: 'template_required' }).perform
    described_class.new(meeting, 'notice_failed', { kind: 'day_before', reason: 'number_cap' }).perform

    expect(alerts.count).to eq(1)
    expect(alerts.sole.metadata).to include('kind' => 'booked', 'reason' => 'template_required')
    expect(Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notice_failed').count).to eq(2)
  end

  it 'outra reunião do mesmo card chama de novo' do
    other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))

    described_class.new(meeting, 'notice_failed', { kind: 'booked', reason: 'template_required' }).perform
    described_class.new(other, 'notice_failed', { kind: 'booked', reason: 'template_required' }).perform

    expect(alerts.pluck(Arel.sql("metadata->>'meeting_id'"))).to contain_exactly(meeting.id.to_s, other.id.to_s)
  end

  it 'o que o cliente fez pela página também é alerta do agendamento, sem tipo nem motivo de aviso' do
    described_class.new(meeting, 'canceled').perform

    expect(alerts.sole.metadata).to eq(
      'source' => 'booking_agent_alert', 'event' => 'canceled', 'meeting_id' => meeting.id,
      'contact_name' => 'Marcos Lima', 'starts_at' => '2026-10-20T13:00:00Z'
    )
  end
end
