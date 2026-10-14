require 'rails_helper'

RSpec.describe Crm::InboxAiAgent do
  include_context 'with crm responsible agent'

  let(:other_account) { create(:account) }

  def build_row(overrides = {})
    described_class.new({ account: account, inbox: inbox, pipeline: comercial, agent: area }.merge(overrides))
  end

  it 'aceita o agente vinculado como área na caixa' do
    expect(build_row).to be_valid
  end

  it 'recusa agente sem vínculo de área ativo na caixa: onde ele trabalha é do Agentes IA' do
    sem_vinculo = criar_agente('Sem caixa')
    expect(build_row(agent: sem_vinculo)).not_to be_valid

    area_sumiu!
    row = build_row
    expect(row).not_to be_valid
    expect(row.errors[:agent]).to include('must work as an area in the inbox')
  end

  it 'recusa a porta: funil sem área fica com ela, sem linha' do
    row = build_row(agent: agente_da_porta)

    expect(row).not_to be_valid
    expect(row.errors[:agent]).to include('must work as an area in the inbox')
  end

  it 'recusa um segundo agente para o mesmo par caixa/funil' do
    outra = criar_agente('Outra')
    Autonomia::Agents::Areas.vincular!(agent: outra, inbox: inbox)
    row = build_row(pipeline: suporte, agent: outra)

    expect(row).not_to be_valid
    expect(row.errors[:pipeline_id]).to be_present
  end

  it 'aceita o mesmo funil em outra caixa em que o agente também é área' do
    outra_caixa = create(:inbox, account: account)
    Autonomia::Agents::Operate::InboxConnector.new(agent: criar_agente('Outra porta'), inbox: outra_caixa).perform(connect: true)
    Autonomia::Agents::Areas.vincular!(agent: area, inbox: outra_caixa)

    expect(build_row(inbox: outra_caixa, pipeline: suporte)).to be_valid
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
    area.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    row = build_row
    expect(row).not_to be_valid
    expect(row.errors[:agent]).to include('must not be deleted')
  end
end
