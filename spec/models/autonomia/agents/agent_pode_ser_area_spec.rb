require 'rails_helper'

# #1433 — quem pode ser oferecido como agente da equipe (área): Agent#pode_ser_area? e o escopo podem_ser_area, que é o
# mesmo predicado em SQL (a lista do CRM, "Quem cuida do quê?").
RSpec.describe Autonomia::Agents::Agent do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def agente(nome, conta: account, **attrs)
    described_class.create!({ account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def conectar(agent, caixa = inbox)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true).agent_inbox
  end

  # Para sem passar pela parada automática: o agente pausado de propósito, com a caixa ainda dele.
  def pausar(agent)
    agent.update_columns(status: described_class.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations
    agent
  end

  describe '#pode_ser_area?' do
    it 'aceita quem está atendendo, com ou sem caixa' do
      com_caixa = agente('Porta').tap { |agent| conectar(agent) }

      expect(agente('Financeiro').pode_ser_area?).to be(true)
      expect(com_caixa.pode_ser_area?).to be(true)
    end

    it 'aceita quem parou por ter ficado sem onde trabalhar' do
      expect(agente('Parado', status: :paused, enabled: false).pode_ser_area?).to be(true)
      expect(agente('Desligado', enabled: false).pode_ser_area?).to be(true)
    end

    it 'recusa quem foi pausado de propósito e ainda tem caixa' do
      pausado = pausar(agente('Pausado').tap { |agent| conectar(agent) })

      expect(pausado.pode_ser_area?).to be(false)
      expect(pausado.motivo_para_nao_ser_area).to eq(:fora_da_equipe)
    end

    it 'recusa o rascunho; com de_rascunho, só o que tem a conversa de criação fechada (instrução)' do
      pela_metade = agente('Novo', status: :draft, enabled: false)
      pronto = agente('Pronto', status: :draft, enabled: false, instruction: 'Atende o financeiro.')

      expect(pela_metade.pode_ser_area?).to be(false)
      expect(pronto.pode_ser_area?).to be(false)
      expect(pela_metade.motivo_para_nao_ser_area(de_rascunho: true)).to eq(:rascunho)
      expect(pronto.motivo_para_nao_ser_area(de_rascunho: true)).to be_nil
    end

    it 'recusa interno, de sistema, ajudante, apagado e a Lia (Agente de Cotação)' do
      apagado = agente('Apagado')
      apagado.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(agente('Copiloto', actuation: :internal).motivo_para_nao_ser_area).to eq(:interno)
      expect(agente('Guia', config: { 'system_key' => 'platform_guide' }).motivo_para_nao_ser_area).to eq(:sistema)
      expect(agente('Ajudante', actuation: :internal, config: { 'papel' => 'ajudante' }).pode_ser_area?).to be(false)
      expect(agente('Ajudante externo', config: { 'papel' => 'ajudante' }).motivo_para_nao_ser_area).to eq(:fora_da_equipe)
      expect(apagado.motivo_para_nao_ser_area).to eq(:fora_da_equipe)
      expect(agente('Lia', agent_type: 'insurance_quote').motivo_para_nao_ser_area).to eq(:fora_da_equipe)
    end
  end

  describe '.podem_ser_area' do
    it 'traz exatamente quem pode_ser_area?, numa consulta só, e só da conta pedida' do
      outra = create(:account)
      agente('De fora', conta: outra)
      agente('Atendendo')
      agente('Parado sem caixa', status: :paused, enabled: false)
      pausar(agente('Pausado com caixa').tap { |agent| conectar(agent) })
      agente('Rascunho', status: :draft, enabled: false, instruction: 'Pronto.')
      agente('Copiloto', actuation: :internal)
      agente('Guia', config: { 'system_key' => 'platform_guide' })
      agente('Ajudante externo', config: { 'papel' => 'ajudante' })
      agente('Lia', agent_type: 'insurance_quote')
      agente('Apagado').update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      consultas = 0
      contar = ->(*, payload) { consultas += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
      nomes = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
        described_class.podem_ser_area(account).order(:name).map(&:name)
      end

      expect(nomes).to eq(['Atendendo', 'Parado sem caixa'])
      expect(consultas).to eq(1)
      expect(described_class.where(account: account).select(&:pode_ser_area?).map(&:name)).to match_array(nomes)
    end

    it 'vínculo de outra conta não conta como caixa do agente' do
      parado = agente('Parado', status: :paused, enabled: false)
      outra = create(:account)
      # Vínculo inválido (o AgentInbox recusa conta diferente): só existe gravado por fora, como defesa.
      Autonomia::Agents::AgentInbox.insert_all!( # rubocop:disable Rails/SkipsModelValidations
        [{ autonomia_agent_id: parado.id, inbox_id: create(:inbox, account: outra).id, account_id: outra.id, papel: 'porta',
           agent_bot_id: create(:agent_bot, account: outra).id, created_at: Time.current, updated_at: Time.current }]
      )

      expect(described_class.podem_ser_area(account)).to contain_exactly(parado)
      expect(parado.reload.pode_ser_area?).to be(true)
    end
  end
end
