require 'rails_helper'

# #858 etapa 2 — a mesma garantia das regras vale para as automações de etapa do CRM: deixar ligada uma
# automação com Decisor não tem desfazer (ela já agiu) e pede a confirmação da pessoa.
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:etapa) { create_crm_pipeline(account: conta, user: admin).last }
  let(:decisor) { create(:autonomia_decisor, account: conta, leituras: %w[card]) }
  let(:passo_do_decisor) { { action_type: 'perguntar_ao_decisor', action_config: { decisor_id: decisor.id, chave_que_segue: 'sim' } } }
  let(:acoes) { described_class.new(account: conta, user: admin) }

  def automacao(enabled:)
    conta.crm_stage_automations.create!(pipeline: etapa.pipeline, stage: etapa, name: 'Grande', trigger_event: :on_enter, enabled: enabled)
  end

  it 'criar a automação de etapa com Decisor desligada continua direto; ligada (ou sem dizer) pede confirmação' do
    criar = 'POST crm/stages/:stage_id/stage_automations'
    dados = ->(corpo) { { caminho: { stage_id: etapa.id }, corpo: { name: 'Grande', steps: [passo_do_decisor] }.merge(corpo) } }

    expect(acoes.desfazivel?(criar, dados.call(enabled: false))).to be(true)
    expect(acoes.desfazivel?(criar, dados.call({}))).to be(false)
    expect(acoes.desfazivel?(criar, { caminho: { stage_id: etapa.id }, corpo: { stage_automation: { name: 'G', steps: [passo_do_decisor] } } }))
      .to be(false)
  end

  it 'ligar a automação que tem o passo, ou pôr o passo numa automação ligada, pede confirmação' do
    desligada = automacao(enabled: false)
    desligada.steps.create!(account: conta, **passo_do_decisor)
    ligada = automacao(enabled: true)

    expect(acoes.desfazivel?('PATCH crm/stage_automations/:id', { caminho: { id: desligada.id }, corpo: { enabled: true } })).to be(false)
    expect(acoes.desfazivel?('POST crm/stage_automations/:stage_automation_id/steps',
                             { caminho: { stage_automation_id: ligada.id }, corpo: passo_do_decisor })).to be(false)
    expect(acoes.desfazivel?('POST crm/stage_automations/:stage_automation_id/steps',
                             { caminho: { stage_automation_id: desligada.id }, corpo: passo_do_decisor })).to be(true)
  end
end
