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
    account.enable_features!('automacao_fundacao')
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

  def contextos_das_sequencias
    contextos = []
    allow(Crm::StageAutomations::StepSequence).to receive(:new).and_wrap_original do |original, **args|
      contextos << args[:automation_context].to_h
      original.call(**args)
    end
    contextos
  end

  it 'sem a flag, o contexto das automações de etapa não leva a cadeia (passos em job e espera do Decisor)' do
    ao_entrar(etapas[0], mover_para: etapas[1])
    contextos = contextos_das_sequencias

    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: etapas[0]).perform

    expect(contextos).not_to be_empty
    expect(contextos).to all(satisfy { |contexto| !contexto.key?('cadeia') })
  end

  it 'com a flag, o contexto das automações de etapa leva a cadeia' do
    account.enable_features!('automacao_fundacao')
    automacao = ao_entrar(etapas[0], mover_para: etapas[1])
    contextos = contextos_das_sequencias

    Crm::Cards::Mover.new(card: card, actor: admin, target_stage: etapas[0]).perform

    expect(contextos.first['cadeia']).to eq(["etapa:#{automacao.id}"])
  end

  # Rollback: o passo entrou na fila com a flag ligada e roda depois de ela ser desligada.
  it 'o passo em job enfileirado com a cadeia, rodando sem a flag, roda sem cadeia' do
    vista = :nao_rodou
    allow(Crm::StageAutomations::StepExecutor).to receive(:new).and_wrap_original do |original, **args|
      vista = Autonomia::Automacao::Cadeia.ativa?
      original.call(**args)
    end
    passo = ao_entrar(etapas[0], mover_para: etapas[1]).steps.first

    Crm::StageAutomationStepJob.perform_now(card_id: card.id, step_id: passo.id, automation_context: { 'cadeia' => ['regra:5'] })

    expect(vista).to be(false)
  end

  # A volta do Decisor de uma regra (PerguntarJob) segue na mesma cadeia: a profundidade não volta a zero.
  describe 'o job do Decisor da regra' do
    include ActiveJob::TestHelper

    let(:rule) { create(:automation_rule, account: account) }

    def enfileirar_dentro_da_cadeia
      Autonomia::Automacao::Cadeia.com('etapa:1', account.id) do
        Autonomia::Decisores::PerguntarJob.perform_later(rule.id, conversation.id, 0, 0)
      end
      enqueued_jobs.find { |job| job['job_class'] == 'Autonomia::Decisores::PerguntarJob' }
    end

    def cadeia_ao_rodar(job_data)
      vista = :nao_rodou
      allow(AutomationRule).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        vista = Autonomia::Automacao::Cadeia.origens
        original.call(*args, **kwargs)
      end
      ActiveJob::Base.execute(job_data)
      vista
    end

    it 'leva a cadeia no job e a devolve ao rodar' do
      account.enable_features!('automacao_fundacao')
      job_data = enfileirar_dentro_da_cadeia

      expect(job_data['autonomia_cadeia']).to eq('conta' => account.id, 'origens' => ['etapa:1'])
      expect(cadeia_ao_rodar(job_data)).to eq(['etapa:1'])
      expect(Autonomia::Automacao::Cadeia.origens).to eq([])
    end

    it 'a nova tentativa do job leva a cadeia de novo' do
      job = Autonomia::Decisores::PerguntarJob.deserialize(enfileirar_dentro_da_cadeia)

      expect(job.serialize['autonomia_cadeia']).to eq('conta' => account.id, 'origens' => ['etapa:1'])
    end

    it 'enfileirado com a cadeia e rodando sem a flag, roda sem cadeia' do
      expect(cadeia_ao_rodar(enfileirar_dentro_da_cadeia)).to eq([])
    end

    it 'fora de uma cadeia, o job sai como sempre' do
      Autonomia::Decisores::PerguntarJob.perform_later(rule.id, conversation.id, 0, 0)

      expect(enqueued_jobs.last).not_to have_key('autonomia_cadeia')
    end
  end
end
