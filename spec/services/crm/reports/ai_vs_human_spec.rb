require 'rails_helper'

# #2000 — o "IA vs humano" virou uma frase na Gestão de IA, que soma os funis que a pessoa enxerga (`todos_os_funis`).
RSpec.describe Crm::Reports::AiVsHuman do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }

  def sugestao(funil, status)
    pipeline, stage = funil
    destino = create_crm_stage(account: account, pipeline: pipeline, name: "Etapa #{SecureRandom.hex(2)}")
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: "Card #{SecureRandom.hex(3)}")
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: destino, confidence: 0.9, model_used: 'test',
                                             status: status)
  end

  def relatorio(params, pipelines: account.crm_pipelines)
    described_class.new(account: account, params: params, pipelines: pipelines).perform
  end

  before do
    vendas.first.update!(is_default: true)
    sugestao(vendas, :auto_applied)
    sugestao(vendas, :accepted)
    sugestao(suporte, :auto_applied)
    sugestao(suporte, :dismissed)
  end

  it 'sem todos_os_funis, conta um funil só (o escolhido ou o padrão)' do
    expect(relatorio({})).to include(ai_auto_moves: 1, ai_accepted: 1, ai_dismissed: 0)
    expect(relatorio({ pipeline_id: suporte.first.id })).to include(ai_auto_moves: 1, ai_accepted: 0, ai_dismissed: 1)
  end

  it 'com todos_os_funis, soma os funis que a pessoa enxerga, e só eles' do
    expect(relatorio({ todos_os_funis: 'true' })).to include(ai_auto_moves: 2, ai_accepted: 1, ai_dismissed: 1)
    so_vendas = account.crm_pipelines.where(id: vendas.first.id)
    expect(relatorio({ todos_os_funis: 'true' }, pipelines: so_vendas)).to include(ai_auto_moves: 1, ai_accepted: 1, ai_dismissed: 0)
  end
end
