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

    it 'é nil com o agente parado: quem não fala com cliente agora não recebe a conversa' do
      area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.responsible_agent(inbox: inbox, pipeline: suporte)).to be_nil
      expect(described_class.destinos_para(conversation)).to eq([])
    end
  end

  describe 'sem a Fase 2 dos Agentes' do
    it 'não há responsável nem destino: quem responde é a porta' do
      Autonomia::Agents::Fase2.desligar!(account)
      conversation.reload # a conta relida, como numa requisição ou job novo

      expect(described_class.areas_ligadas?(account)).to be(false)
      expect(described_class.responsible_agent(inbox: inbox, pipeline: suporte)).to be_nil
      expect(described_class.destinos_para(conversation)).to eq([])
    end

    it 'nem com os Agentes desligados na conta' do
      allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

      expect(described_class.areas_ligadas?(account)).to be(false)
      expect(described_class.destinos_para(conversation)).to eq([])
    end
  end

  describe '.destinos_para' do
    it 'lista o funil com responsável que é área da caixa' do
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
      Autonomia::Agents::Operate::InboxConnector.new(agent: criar_agente('Outra porta'), inbox: outra).perform(connect: true)
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: outra)
      account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: outra, default_stage: comercial.stages.first, created_by: admin)
      Crm::InboxAiAgent.create!(account: account, inbox: outra, pipeline: comercial, agent: area)

      expect(described_class.destinos_para(conversation).pluck(:pipeline_id)).to eq([suporte.id])
    end

    it 'exige o vínculo de área ativo: se ele some por fora, a linha fica sem efeito' do
      area_sumiu!

      expect(described_class.destinos_para(conversation)).to eq([])
      expect(Crm::InboxAiAgent.where(inbox: inbox)).to exist
    end

    it 'deixa de fora funil arquivado ou com a IA do funil desligada' do
      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => false)))
      expect(described_class.destinos_para(conversation)).to eq([])

      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => true)), status: :archived)
      expect(described_class.destinos_para(conversation)).to eq([])
    end
  end
end
