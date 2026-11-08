require 'rails_helper'

# Garantia pedida pela Automação no #2694 (F2): o card que a Prospecção cria, com e sem dono escolhido, continua
# avisando a Automação livre (o emissor do CRM despacha, a Escuta ouve o evento do card e a marca da atividade
# abre uma execução só) e roda a automação de etapa da etapa inicial (Crm::StageAutomations::Runner, uma execução
# marcada pelo trigger_token da entrada).
RSpec.describe Autonomia::Prospecting::CrmCardConverter, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:colleague) { create_crm_agent(account: account, name: 'Lucas Andrade').first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    stage
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila (como em gatilhos_de_card_spec.rb).
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "automacao-#{index}", name: "Empresa #{index}")
  end

  def stage_automation
    automation = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Entrada', trigger_event: :on_enter,
                                                       created_by: admin)
    # Passo inofensivo: só um lembrete, nenhuma mensagem ao cliente.
    automation.steps.create!(account: account, position: 0, delay_seconds: 0, action_type: :create_follow_up,
                             action_config: { title: 'Ligar para o decisor', automation_mode: 'reminder_only' })
    automation
  end

  def convert(lead, owner_id: nil)
    described_class.new(lead: lead, user: admin, pipeline_id: pipeline.id, stage_id: stage.id, owner_id: owner_id).perform.card
  end

  [nil, :colleague].each do |owner|
    context(owner ? 'com dono escolhido' : 'sem dono escolhido') do
      let(:owner_id) { owner && colleague.id }

      it 'o card convertido começa "criado" e "entrou na etapa" da etapa inicial, uma vez, pela marca da atividade', :aggregate_failures do
        criado = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.criado' })
        entrou = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => stage.id })

        card = convert(create_lead(1), owner_id: owner_id)
        drenar

        atividade = Crm::Activity.where(card: card, event_type: 'create').sole
        expect(card.owner_id).to eq(owner_id || admin.id)
        expect(execucoes.where(automacao: criado).sole).to have_attributes(alvo: card)
        expect(execucoes.where(automacao: entrou).sole.evento).to eq("card.entrou_na_etapa:atividade:#{atividade.id}")
      end

      it 'o card convertido roda a automação de etapa da etapa inicial' do
        automation = stage_automation

        card = convert(create_lead(2), owner_id: owner_id)

        execution = Crm::StageAutomationExecution.where(card: card, stage_automation: automation).sole
        expect(execution.trigger_token).to include(stage.id.to_s)
      end
    end
  end
end
