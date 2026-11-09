require 'rails_helper'

# Dono escolhido vence a automação de entrada da etapa (#2694, decisão do Rodrigo em 08/11). A Prospecção cria o card
# com o dono escolhido e roda a automação de entrada com `dono_escolhido` no automation_context; o passo "atribuir
# dono" mantém o dono, registra `automation_owner_kept` e a sequência segue. Sem escolha, tudo como antes. A atividade de
# criação leva `owner_chosen: true` só quando a pessoa escolheu.
RSpec.describe Autonomia::Prospecting::CrmCardConverter do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:colleague) { create_crm_agent(account: account, name: 'Lucas Andrade').first }
  let(:rule_owner) { create_crm_agent(account: account, name: 'Paula Ribeiro').first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "dono-#{index}", name: "Empresa #{index}")
  end

  def entry_automation(*steps)
    automation = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Entrada', trigger_event: :on_enter,
                                                       created_by: admin)
    steps.each_with_index do |(action_type, action_config, delay), position|
      automation.steps.create!(account: account, position: position, delay_seconds: delay || 0, action_type: action_type,
                               action_config: action_config)
    end
    automation
  end

  def assign_rule_owner = [:assign_owner, { owner_id: rule_owner.id }]

  def convert(owner_id: nil)
    described_class.new(lead: create_lead(1), user: admin, pipeline_id: pipeline.id, stage_id: stage.id, owner_id: owner_id).perform.card
  end

  def execution_of(card) = Crm::StageAutomationExecution.where(card: card).sole

  it 'com dono escolhido, o "atribuir dono" da entrada mantém o dono e a linha do tempo diz isso', :aggregate_failures do
    entry_automation(assign_rule_owner)

    card = convert(owner_id: colleague.id)

    expect(card.reload.owner_id).to eq(colleague.id)
    kept = Crm::Activity.where(card: card, event_type: 'automation_owner_kept').sole
    expect(kept.payload).to include('owner_id' => colleague.id)
    expect(Crm::Activity.where(card: card, event_type: 'automation_owner_assigned')).to be_empty
    expect(execution_of(card)).to be_completed
  end

  it 'sem dono escolhido, a automação de entrada atribui o dono como hoje', :aggregate_failures do
    entry_automation(assign_rule_owner)

    card = convert

    expect(card.reload.owner_id).to eq(rule_owner.id)
    expect(Crm::Activity.where(card: card, event_type: 'automation_owner_assigned').count).to eq(1)
    expect(Crm::Activity.where(card: card, event_type: 'automation_owner_kept')).to be_empty
  end

  it 'com atraso no "atribuir dono", o passo que roda depois no job também mantém o dono escolhido' do
    entry_automation([:assign_owner, { owner_id: rule_owner.id }, 3600])

    card = convert(owner_id: colleague.id)
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Crm::StageAutomationStepJob)
    perform_enqueued_jobs(only: Crm::StageAutomationStepJob)

    expect(card.reload.owner_id).to eq(colleague.id)
    expect(Crm::Activity.where(card: card, event_type: 'automation_owner_kept').count).to eq(1)
  end

  it 'com "atribuir dono" e "criar retorno", o dono fica, o retorno é criado e a execução termina', :aggregate_failures do
    entry_automation(assign_rule_owner, [:create_follow_up, { title: 'Ligar para o decisor', automation_mode: 'reminder_only' }])

    card = convert(owner_id: colleague.id)

    expect(card.reload.owner_id).to eq(colleague.id)
    expect(account.crm_follow_ups.where(card: card).count).to eq(1)
    expect(execution_of(card)).to be_completed
  end

  describe 'marca owner_chosen na atividade de criação' do
    def create_activity(card) = Crm::Activity.where(card: card, event_type: 'create').sole

    it 'com dono escolhido, a atividade de criação tem owner_chosen: true' do
      expect(create_activity(convert(owner_id: colleague.id)).payload).to include('owner_chosen' => true)
    end

    it 'sem dono escolhido, a chave owner_chosen não existe' do
      expect(create_activity(convert).payload).not_to have_key('owner_chosen')
    end
  end
end
