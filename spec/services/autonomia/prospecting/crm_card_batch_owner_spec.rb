require 'rails_helper'

# Dono escolhido na Prospecção nova (#2694, F2): o CrmCardBatch confere o dono contra o funil antes de tentar qualquer
# lead, e o CrmCardConverter o repassa ao Crm::Cards::Creator. Sem owner_id, tudo como antes.
RSpec.describe Autonomia::Prospecting::CrmCardBatch do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:colleague) { create_crm_agent(account: account, name: 'Lucas Andrade').first }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "owner-svc-#{index}", name: "Empresa #{index}")
  end

  def perform(lead_ids, **extra)
    described_class.new(account: account, user: user, lead_ids: lead_ids, pipeline_id: pipeline.id, stage_id: stage.id, **extra).perform
  end

  it 'com owner_id, os cards criados ficam com a pessoa escolhida e a linha do tempo diz quem' do
    result = perform([create_lead(1).id, create_lead(2).id], owner_id: colleague.id)

    expect(result.created.size).to eq(2)
    expect(account.crm_cards.pluck(:owner_id)).to eq([colleague.id, colleague.id])
    expect(Crm::Activity.where(event_type: 'create').map { |activity| activity.payload['owner_id'] }).to eq([colleague.id, colleague.id])
  end

  it 'sem owner_id, o card fica com quem manda, como antes' do
    perform([create_lead(1).id])

    expect(account.crm_cards.sole.owner_id).to eq(user.id)
  end

  it 'dono de outra conta: recusa o lote inteiro e nada é criado' do
    other = create(:account)
    stranger = create(:user, :administrator, account: other)
    lead = create_lead(1)

    expect { perform([lead.id], owner_id: stranger.id) }.to raise_error(Autonomia::Prospecting::CrmCardOwner::NotAllowed)
    expect(account.crm_cards.count).to eq(0)
    expect(lead.reload.contact_id).to be_nil
  end

  it 'dono que não enxerga o funil: recusa o lote inteiro' do
    Crm::PipelineInbox.create!(account: account, inbox: create_crm_inbox(account: account, name: 'Filial'), pipeline: pipeline)
    own_inbox = create_crm_inbox(account: account, name: 'Vendas', members: [colleague])
    access = Crm::InboxAgentAccess.create!(account: account, inbox: own_inbox, user: colleague, all_pipelines: false, triage: false,
                                           only_own: false)
    access.agent_pipelines.create!(account: account, pipeline: create_crm_pipeline(account: account, user: user, name: 'Outro').first)

    expect { perform([create_lead(1).id], owner_id: colleague.id) }.to raise_error(Autonomia::Prospecting::CrmCardOwner::NotAllowed)
    expect(account.crm_cards.count).to eq(0)
  end

  it 'dono que não vê os cards do CRM (função sem crm_view): recusa o lote inteiro' do
    sem_crm = create(:user, account: account, role: :agent)
    sem_crm.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: ['prospecting_manage']))

    expect { perform([create_lead(1).id], owner_id: sem_crm.id) }.to raise_error(Autonomia::Prospecting::CrmCardOwner::NotAllowed)
    expect(account.crm_cards.count).to eq(0)
  end

  # Conta sem acesso por funil: ninguém é calculado pessoa a pessoa.
  it 'sem acesso por funil na conta, não calcula o funil de cada pessoa' do
    allow(Crm::Access::VisiblePipelines).to receive(:new).and_call_original

    perform([create_lead(1).id], owner_id: colleague.id)

    expect(Crm::Access::VisiblePipelines).to have_received(:new).once # só o funil de quem manda (ensure_destination!)
  end

  describe Autonomia::Prospecting::CrmCardConverter do
    it 'repassa o owner_id ao card criado' do
      result = described_class.new(lead: create_lead(1), user: user, pipeline_id: pipeline.id, stage_id: stage.id, owner_id: colleague.id).perform

      expect(result.card.owner_id).to eq(colleague.id)
    end

    it 'sem owner_id, o card fica com quem manda' do
      result = described_class.new(lead: create_lead(1), user: user, pipeline_id: pipeline.id, stage_id: stage.id).perform

      expect(result.card.owner_id).to eq(user.id)
    end
  end
end
