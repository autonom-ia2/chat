require 'rails_helper'

# #1920: o movimento que não foi escolha direta de uma pessoa grava a origem, e a evidência e o raio-x o deixam de fora.
RSpec.describe Crm::Cards::Mover do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline_and_stage.first, name: 'Proposta') }
  let(:card) { account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Pedido') }

  def mover(automacao: nil, **contexto)
    described_class.new(card: card, actor: admin, target_stage: proposta, automation_context: contexto, automacao: automacao).perform
    Crm::Activity.where(card: card, event_type: 'move').last
  end

  it 'grava só as etapas quando uma pessoa move direto' do
    movimento = mover

    expect(movimento.payload.keys).to match_array(%w[from_pipeline_id to_pipeline_id from_stage_id to_stage_id from_stage_name to_stage_name])
    expect(Crm::Ai::EscolhaDePessoa.movimentos(account.id, desde: 1.hour.ago)).to include(movimento)
  end

  it 'grava a origem da automação e do agendamento' do
    automacao = mover(depth: 1, skip_automations: true)

    expect(automacao.payload).to include('automation_depth' => 1)
    expect(Crm::Ai::EscolhaDePessoa.movimentos(account.id, desde: 1.hour.ago)).not_to include(automacao)
    card.update!(stage: pipeline_and_stage.last)
    expect(mover(source: 'booking_post_meeting', skip_automations: true).payload).to include('source' => 'booking_post_meeting')
  end

  it 'deixa de fora o movimento do motor novo de automação (by: automacao)' do
    movimento = mover(skip_automations: true, automacao: { origem: 'regra', id: 1 })

    expect(movimento.payload).to include('by' => 'automacao')
    expect(Crm::Ai::EscolhaDePessoa.movimentos(account.id, desde: 1.hour.ago)).not_to include(movimento)
  end

  it 'deixa de fora o movimento em lote de quem arquiva o funil ou apaga a etapa (motivo)' do
    lote = Crm::Activity.create!(account_id: account.id, card_id: card.id, actor_type: 'user', actor_id: admin.id, event_type: 'move',
                                 payload: { from_stage_id: card.stage_id, to_stage_id: proposta.id, motivo: 'etapa_apagada' })

    expect(Crm::Ai::EscolhaDePessoa.movimentos(account.id, desde: 1.hour.ago)).not_to include(lote)
  end

  it 'grava o motivo da etapa de entrada e o nome do funil, e deixa o movimento de fora da escolha da pessoa (#2501)' do
    described_class.new(card: card, actor: admin, target_stage: proposta, automation_context: { skip_automations: true },
                        etapa_de_entrada: Crm::Cards::EtapaDeEntrada::SEM_ETAPA).perform
    movimento = Crm::Activity.where(card: card, event_type: 'move').last

    expect(movimento.payload).to include('motivo' => 'etapa_nao_veio', 'to_pipeline_name' => 'Funil Comercial')
    expect(Crm::Ai::EscolhaDePessoa.movimentos(account.id, desde: 1.hour.ago)).not_to include(movimento)
  end
end
