require 'rails_helper'

RSpec.describe Crm::Ai::Config do
  include_context 'with crm responsible agent'

  describe '.responsible_agent' do
    it 'devolve o agente gravado para a caixa e o funil' do
      expect(described_class.responsible_agent(inbox: inbox, pipeline: suporte)).to eq(area)
    end

    it 'não cruza contas mesmo com uma linha inconsistente gravada por fora da validação' do
      outra = create(:account)
      alheio = Autonomia::Agents::Agent.create!(account: outra, name: 'Alheio', agent_type: 'custom')
      Crm::InboxAiAgent.find_by(pipeline: suporte).update_columns(autonomia_agent_id: alheio.id) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.responsible_agent(inbox: inbox, pipeline: suporte)).to be_nil
      expect(described_class.destinos_para(conversation)).to eq([])
    end

    it 'é nil para funil sem responsável e para agente apagado' do
      expect(described_class.responsible_agent(inbox: inbox, pipeline: comercial)).to be_nil

      area.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.responsible_agent(inbox: inbox, pipeline: suporte)).to be_nil
    end
  end

  describe '.destinos_para' do
    it 'lista o funil com responsável ligado à caixa' do
      create_card(pipeline: comercial)

      expect(described_class.destinos_para(conversation))
        .to eq([{ pipeline_id: suporte.id, nome: 'Suporte', agente_id: area.id, agente_nome: 'Área Suporte' }])
    end

    it 'deixa de fora o funil do assunto em atendimento' do
      create_card(pipeline: suporte)

      expect(described_class.destinos_para(conversation)).to eq([])
    end

    it 'filtra pela caixa da conversa: o responsável de outra caixa não entra' do
      outra = create(:inbox, account: account)
      account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: outra, default_stage: comercial.stages.first, created_by: admin)
      Crm::InboxAiAgent.create!(account: account, inbox: outra, pipeline: comercial, agent: area)

      expect(described_class.destinos_para(conversation).pluck(:pipeline_id)).to eq([suporte.id])
    end

    it 'exige o agente ligado à caixa: sem vínculo (área antes da F1) a lista sai vazia' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Comercial IA', agent_type: 'custom')
      Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: comercial, agent: outro)
      Autonomia::Agents::AgentInbox.where(agent: area).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.destinos_para(conversation)).to eq([])
    end

    it 'deixa de fora funil arquivado ou com a IA do funil desligada' do
      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => false)))
      expect(described_class.destinos_para(conversation)).to eq([])

      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => true)), status: :archived)
      expect(described_class.destinos_para(conversation)).to eq([])
    end
  end

  describe '.area_de_algum_funil?' do
    it 'diz se o agente cuida de algum funil' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Sem funil', agent_type: 'custom')

      expect(described_class.area_de_algum_funil?(area)).to be(true)
      expect(described_class.area_de_algum_funil?(outro)).to be(false)

      area.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.area_de_algum_funil?(area)).to be(false)
    end
  end
end
