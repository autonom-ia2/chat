require 'rails_helper'

RSpec.describe Crm::StageAutomations::StepExecutor do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  def build_step(account:, stage:, user:, action_type:, action_config: {}, delay_seconds: 0)
    automation = account.crm_stage_automations.create!(
      pipeline: stage.pipeline,
      stage: stage,
      name: 'Executor test',
      trigger_event: :on_enter,
      created_by: user
    )
    automation.steps.create!(
      account: account,
      position: 0,
      delay_seconds: delay_seconds,
      action_type: action_type,
      action_config: action_config
    )
  end

  it 'assigns an owner to the card' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead')
    step = build_step(
      account: account,
      stage: stage,
      user: admin,
      action_type: :assign_owner,
      action_config: { owner_id: agent.id }
    )

    result = described_class.new(card: card, step: step, actor: admin).perform

    expect(result.status).to eq(:ok)
    expect(card.reload.owner_id).to eq(agent.id)
  end

  it 'moves the card to another stage' do
    account, admin = create_account_and_user
    pipeline, first_stage = create_crm_pipeline(account: account, user: admin)
    second_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Lead')
    step = build_step(
      account: account,
      stage: first_stage,
      user: admin,
      action_type: :move_stage,
      action_config: { target_stage_id: second_stage.id }
    )

    result = described_class.new(card: card, step: step, actor: admin).perform

    expect(result.status).to eq(:ok)
    expect(card.reload.stage_id).to eq(second_stage.id)
    # #2428: o movimento leva a automação de etapa, para a IA do funil não desfazê-lo.
    movimento = Crm::Activity.where(card: card, event_type: 'move').sole
    expect(movimento.payload).to include('by' => 'automacao', 'origem' => 'etapa', 'automacao_id' => step.stage_automation_id)
  end

  it 'blocks move_stage when automation depth is exceeded' do
    account, admin = create_account_and_user
    pipeline, first_stage = create_crm_pipeline(account: account, user: admin)
    second_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Lead')
    step = build_step(
      account: account,
      stage: first_stage,
      user: admin,
      action_type: :move_stage,
      action_config: { target_stage_id: second_stage.id }
    )

    result = described_class.new(
      card: card,
      step: step,
      actor: admin,
      automation_context: { depth: Crm::StageAutomations::StepExecutor::MAX_AUTOMATION_DEPTH }
    ).perform

    expect(result.status).to eq(:failed)
    expect(result.error).to eq('automation_depth_exceeded')
  end
end
