require 'rails_helper'

RSpec.describe Crm::Cards::ActivityPayloadBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  # A timeline mostra "Reunião passou para <nome>": o nome de quem recebeu vem resolvido em labels.to_user_id.
  it 'resolve o nome de quem recebeu a reunião reatribuída' do
    activity = Crm::Activity.create!(account: account, card: world.card, actor_type: 'system', event_type: 'meeting_host_reassigned',
                                     payload: { 'meeting_id' => 1, 'from_user_id' => 999_999, 'to_user_id' => world.host.id })

    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first, activities: [activity]).perform

    expect(payload.first[:labels]).to eq('to_user_id' => world.host.name)
  end

  # Etapa apagada: o histórico continua com o nome dela, gravado na atividade `move` (Crm::Cards::Mover).
  it 'mostra o nome gravado da etapa que não existe mais' do
    pipeline, inicio = create_crm_pipeline(account: account, user: admin)
    proposta = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    card = account.crm_cards.create!(pipeline: pipeline, stage: inicio, title: 'Pedido')
    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: proposta, automation_context: { skip_automations: true }).perform
    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: inicio, automation_context: { skip_automations: true }).perform
    Crm::PipelineStages::Destroyer.new(stage: proposta).perform

    activities = card.activities.where(event_type: 'move').order(:id).to_a
    payload = described_class.new(account: account, user: admin, account_user: admin.account_users.first, activities: activities).perform

    expect(payload.map { |item| item[:labels] }).to eq(
      [{ 'from_stage_id' => 'Novo Lead', 'to_stage_id' => 'Proposta' }, { 'from_stage_id' => 'Proposta', 'to_stage_id' => 'Novo Lead' }]
    )
  end
end
