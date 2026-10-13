require 'rails_helper'

RSpec.describe Crm::InboxAiAgent do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').first }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Área', agent_type: 'custom') }

  def build_row(overrides = {})
    described_class.new({ account: account, inbox: inbox, pipeline: pipeline, agent: agent }.merge(overrides))
  end

  it 'aceita agente de área sem vínculo com a caixa: o vínculo é do Agentes IA (F1, #1433)' do
    expect(build_row).to be_valid
  end

  it 'recusa um segundo agente para o mesmo par caixa/funil' do
    build_row.save!

    other = Autonomia::Agents::Agent.create!(account: account, name: 'Outra', agent_type: 'custom')
    row = build_row(agent: other)

    expect(row).not_to be_valid
    expect(row.errors[:pipeline_id]).to be_present
  end

  it 'aceita o mesmo funil em outra caixa' do
    build_row.save!

    expect(build_row(inbox: create(:inbox, account: account))).to be_valid
  end

  it 'recusa caixa, funil e agente de outra conta' do
    foreign_admin = create(:user, account: other_account, role: :administrator)
    row = build_row(inbox: create(:inbox, account: other_account),
                    pipeline: create_crm_pipeline(account: other_account, user: foreign_admin).first,
                    agent: Autonomia::Agents::Agent.create!(account: other_account, name: 'Alheio', agent_type: 'custom'))

    expect(row).not_to be_valid
    expect(row.errors.attribute_names).to include(:inbox, :pipeline, :agent)
  end

  it 'recusa agente apagado' do
    agent.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    row = build_row
    expect(row).not_to be_valid
    expect(row.errors[:agent]).to include('must not be deleted')
  end
end
