require 'rails_helper'

# #1876: o fechamento grava quem era o responsável, o time e o funil naquela hora. É a base do crédito das metas: uma
# troca de responsável, de time ou de funil depois do fechamento não muda de quem foi a venda.
RSpec.describe Crm::Cards::Closer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:team) { create(:team, account: account) }
  let(:sale) { create_crm_pipeline(account: account, user: admin) }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Suporte', created_by: admin, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end

  def card_in(pipeline_and_stage, owner: seller)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, team: team, title: 'Orçamento', currency: 'BRL')
  end

  def close(card, result, actor: admin)
    described_class.new(card: card, actor: actor, result: result).perform
    card.activities.order(:id).last
  end

  def snapshot(card, responsible)
    { 'responsible' => responsible, 'owner_id' => card.owner_id, 'team_id' => team.id, 'pipeline_id' => card.pipeline_id }
  end

  it 'grava o responsável (não quem clicou), o time e o funil no ganho e na perda' do
    seller_responsible = { 'type' => 'agent', 'id' => seller.id, 'name' => 'Ana' }

    won = card_in(sale)
    expect(close(won, 'won').payload['closed_with']).to eq(snapshot(won, seller_responsible))

    lost = card_in(sale)
    expect(close(lost, 'lost').payload['closed_with']).to eq(snapshot(lost, seller_responsible))
  end

  it 'grava no resolvido e no cancelado de um funil de Atender' do
    seller_responsible = { 'type' => 'agent', 'id' => seller.id, 'name' => 'Ana' }

    resolved = card_in(service)
    activity = close(resolved, 'won')
    expect(activity.event_type).to eq('resolved')
    expect(activity.payload['closed_with']).to eq(snapshot(resolved, seller_responsible))

    cancelled = card_in(service)
    expect(close(cancelled, 'lost').payload['closed_with']).to eq(snapshot(cancelled, seller_responsible))
  end

  it 'grava também quando o fechamento vem de automação, sem autor, e quando não há responsável' do
    card = card_in(sale, owner: nil)

    activity = close(card, 'won', actor: nil)

    expect(activity.actor_type).to eq('system')
    expect(activity.payload['closed_with']).to eq(snapshot(card, nil))
  end

  # IA entende a conversa F3: o fechamento da IA leva quem fechou e o motivo; o desfecho e o responsável não mudam.
  it 'leva o payload_extra na atividade, sem trocar o motivo nem o responsável' do
    card = card_in(sale)
    described_class.new(card: card, actor: nil, result: 'lost', lost_reason: 'Adiou',
                        payload_extra: { by: 'ai', motivo: 'adiou', lost_reason: 'outro' }).perform

    expect(card.activities.order(:id).last.payload)
      .to include('by' => 'ai', 'motivo' => 'adiou', 'lost_reason' => 'Adiou', 'closed_with' => be_present)
  end

  it 'não grava nada ao reabrir' do
    card = card_in(sale)
    close(card, 'won')

    expect(close(card, 'reopen').payload).not_to have_key('closed_with')
  end
end
