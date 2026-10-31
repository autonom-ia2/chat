require 'rails_helper'

# #2414 F1 (D6): regras de automação e automações de etapa do CRM contam na mesma cadeia. Com a flag, a quarta
# automação da sequência e a repetição de uma delas são recusadas. Sem a flag, cada motor faz o que fazia.
RSpec.describe Autonomia::Automacao::CadeiaNosMotores do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:inicio) { pipeline_and_stage.last }
  let(:etapas) { (1..4).map { |n| create_crm_stage(account: account, pipeline: pipeline, name: "Etapa #{n}") } }
  let(:conversation) { create(:conversation, account: account).reload }
  let!(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: inicio, contact: conversation.contact,
                              primary_conversation: conversation, title: 'Lead')
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def ao_entrar(etapa, mover_para:)
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: etapa, name: "Entrou em #{etapa.name}",
                                                      trigger_event: :on_enter, created_by: admin)
    automacao.steps.create!(account: account, position: 0, delay_seconds: 0, action_type: :move_stage,
                            action_config: { target_stage_id: mover_para.id })
    automacao
  end

  def regra_que_move_para(etapa)
    create(:automation_rule, account: account, actions: [{ action_name: 'crm_move_card_stage', action_params: [etapa.id] }])
  end

  # regra → etapa 1 → etapa 2 → etapa 3 → etapa 4: a cadeia é [regra, automação da 1, automação da 2].
  def montar_cascata
    ao_entrar(etapas[0], mover_para: etapas[1])
    ao_entrar(etapas[1], mover_para: etapas[2])
    ao_entrar(etapas[2], mover_para: etapas[3])
    regra_que_move_para(etapas[0])
  end

  it 'com a flag, regra mais duas automações de etapa rodam e a terceira é recusada (profundidade 3)' do
    account.enable_features!('automacao_fundacao')
    regra = montar_cascata
    allow(Rails.logger).to receive(:info).and_call_original

    AutomationRules::ActionService.new(regra, account, conversation).perform

    expect(card.reload.stage_id).to eq(etapas[2].id)
    expect(Rails.logger).to have_received(:info).with(/\[automacao\]\[cadeia\] recusada origem=etapa:\d+ motivo=profundidade/)
  end

  it 'sem a flag, a regra não conta e as automações de etapa seguem o limite de antes' do
    regra = montar_cascata

    AutomationRules::ActionService.new(regra, account, conversation).perform

    expect(card.reload.stage_id).to eq(etapas[3].id)
  end

  # F1.1 no motor de etapas: A leva para a etapa 2, B devolve para a 1, e A não roda de novo na mesma sequência.
  it 'com a flag, a automação que voltaria a rodar na mesma sequência é recusada como laço, e o registro diz por quê' do
    account.enable_features!('automacao_fundacao')
    ida = ao_entrar(etapas[0], mover_para: etapas[1])
    ao_entrar(etapas[1], mover_para: etapas[0])
    allow(Rails.logger).to receive(:info).and_call_original

    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: etapas[0]).perform

    expect(card.reload.stage_id).to eq(etapas[0].id)
    expect(Rails.logger).to have_received(:info).with(/recusada origem=etapa:#{ida.id} motivo=laco/)
  end

  it 'a cadeia viaja com o passo de etapa que roda em job' do
    vista = nil
    allow(Crm::StageAutomations::StepExecutor).to receive(:new).and_wrap_original do |original, **args|
      vista = Autonomia::Automacao::Cadeia.origens
      original.call(**args)
    end
    passo = ao_entrar(etapas[0], mover_para: etapas[1]).steps.first

    Crm::StageAutomationStepJob.perform_now(card_id: card.id, step_id: passo.id,
                                            automation_context: { 'cadeia' => ['regra:5', "etapa:#{passo.stage_automation_id}"] })

    expect(vista).to eq(['regra:5', "etapa:#{passo.stage_automation_id}"])
    expect(Autonomia::Automacao::Cadeia.origens).to eq([])
  end
end
