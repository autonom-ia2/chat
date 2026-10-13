require 'rails_helper'

# #1428 — a versão guarda o AGENTE INTEIRO e voltar a ela devolve tudo. Caso real (13/10, conta 16): o
# Construtor "aplicou" uma pergunta e regravou o agente sem deixar versão; não havia como saber o que
# mudou nem como voltar.
RSpec.describe Autonomia::Agents::AgentVersioning do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:campos) { Autonomia::Agents::AgentVersioning::CAMPOS }
  let(:rascunho) { Autonomia::Agents::Agent.create!(account: account, name: 'Rascunho', agent_type: 'custom') }

  def gerado(sufixo, voz: 'feminina')
    {
      'name' => "Bia #{sufixo}", 'agent_type' => 'support', 'instruction' => "instrucao #{sufixo}",
      'scaffold' => "andaime #{sufixo}", 'human_card' => "cartao #{sufixo}", 'greeting' => "oi #{sufixo}",
      'fallback_message' => "nao sei #{sufixo}", 'handoff_rule' => "passa #{sufixo}",
      'starter_questions' => ["pergunta #{sufixo}"], 'tone' => "tom #{sufixo}",
      'guardrails' => ["limite #{sufixo}"], 'voice' => voz
    }
  end

  def aplicar(agent, parsed)
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, created_by: user,
                                                    status: :processing, build_token: SecureRandom.hex(4))
    agent.apply_builder_config!(thread.build_token, Autonomia::Agents::Builder.map_attributes(parsed))
  end

  # O estado do agente nos campos versionados, lido do banco.
  def retrato(agent)
    agent.reload
    campos.index_with { |campo| agent[campo] }
          .merge('instruction' => agent.instruction, 'guardrails' => agent.config['guardrails'],
                 'voice' => agent.config['voice'])
  end

  describe 'aplicação do Construtor' do
    it 'a criação grava exatamente 1 versão com o agente inteiro' do
      # Act
      aplicar(rascunho, gerado('v1'))

      # Assert
      versoes = rascunho.instruction_versions
      expect(versoes.count).to eq(1)
      versao = versoes.first
      expect([versao.reason, versao.created_by, versao.instruction]).to eq(['builder_create', user, 'instrucao v1'])
      expect(versao.metadata['agente'].keys).to match_array(campos + %w[config])
      expect(versao.metadata['agente']).to include('name' => 'Bia v1', 'scaffold' => 'andaime v1', 'tone' => 'tom v1',
                                                   'starter_questions' => ['pergunta v1'], 'agent_type' => 'support')
      expect(versao.metadata['agente']['config']).to eq('guardrails' => ['limite v1'], 'voice' => 'feminina')
      expect(versao.metadata).not_to have_key('sem_mudanca')
    end

    it 'o ajuste grava exatamente 1 versão por aplicação' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act
      aplicar(rascunho, gerado('v2'))

      # Assert
      expect(rascunho.instruction_versions.order(:id).pluck(:reason)).to eq(%w[builder_create builder_adjust])
      expect(rascunho.instruction_versions.order(:id).last.metadata['agente']['greeting']).to eq('oi v2')
    end

    it 'grava a versão mesmo quando nada mudou, marcando sem_mudanca' do
      # Arrange
      aplicar(rascunho, gerado('v1'))

      # Act
      aplicar(rascunho, gerado('v1'))

      # Assert
      ultima = rascunho.instruction_versions.order(:id).last
      expect(rascunho.instruction_versions.count).to eq(2)
      expect(ultima.reason).to eq('builder_adjust')
      expect(ultima.metadata['sem_mudanca']).to be(true)
    end

    it 'a primeira aplicação num agente sem versão grava antes a versão base com o estado anterior' do
      # Arrange — agente que já existia antes das versões completas
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Antigo', agent_type: 'support',
                                               instruction: 'instrucao antiga', greeting: 'oi antigo',
                                               config: { 'guardrails' => ['antigo'] })

      # Act
      aplicar(agent, gerado('v2'))

      # Assert
      base, aplicacao = agent.instruction_versions.order(:id).to_a
      expect(agent.instruction_versions.count).to eq(2)
      expect(base.reason).to eq('base')
      expect(base.instruction).to eq('instrucao antiga')
      expect(base.metadata['agente']).to include('name' => 'Antigo', 'greeting' => 'oi antigo')
      expect(base.metadata['agente']['config']).to include('guardrails' => ['antigo'])
      expect(aplicacao.reason).to eq('builder_adjust')
    end

    it 'grava a versão base quando só existem versões antigas, só com a instrução' do
      # Arrange
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Antigo', agent_type: 'support',
                                               instruction: 'instrucao antiga')
      agent.instruction_versions.create!(account: account, instruction: 'instrucao antiga', reason: 'kb_refresh',
                                         instruction_hash: Digest::SHA256.hexdigest('instrucao antiga'))

      # Act
      aplicar(agent, gerado('v2'))

      # Assert
      expect(agent.instruction_versions.order(:id).pluck(:reason)).to eq(%w[kb_refresh base builder_adjust])
    end

    it 'aplica sem versão quando o Construtor não devolve instrução' do
      # Act
      venceu = aplicar(rascunho, gerado('v1').merge('instruction' => ''))

      # Assert
      expect(venceu).to be(true)
      expect(rascunho.reload.name).to eq('Bia v1')
      expect(rascunho.instruction_versions.count).to eq(0)
    end

    it 'não grava versão quando a aplicação perde para um ajuste mais novo' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      velha = Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho, status: :processing,
                                                     build_token: 'velho')
      Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho, status: :open)

      # Act
      venceu = rascunho.apply_builder_config!(velha.build_token,
                                              Autonomia::Agents::Builder.map_attributes(gerado('v2')))

      # Assert
      expect(venceu).to be(false)
      expect(rascunho.instruction_versions.count).to eq(1)
    end
  end

  describe 'voltar a uma versão' do
    it 'devolve o agente idêntico, campo a campo' do
      # Arrange
      aplicar(rascunho, gerado('v1', voz: 'masculina'))
      esperado = retrato(rascunho)
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))
      expect(retrato(rascunho)).not_to eq(esperado)

      # Act
      rascunho.restore_instruction!(versao_v1, created_by: user)

      # Assert
      expect(retrato(rascunho)).to eq(esperado)
      volta = rascunho.instruction_versions.order(:id).last
      expect(volta.reason).to eq('rollback')
      expect(volta.metadata['agente']['greeting']).to eq('oi v1')
    end

    it 'preserva as chaves de config que a versão não guarda' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      versao_v1 = rascunho.instruction_versions.order(:id).last
      aplicar(rascunho, gerado('v2'))
      rascunho.update!(config: rascunho.config.merge('topic_map' => { 'precos' => 1 }, 'model' => 'x'))

      # Act
      rascunho.restore_instruction!(versao_v1)

      # Assert
      expect(rascunho.reload.config).to include('topic_map' => { 'precos' => 1 }, 'model' => 'x',
                                                'guardrails' => ['limite v1'])
    end

    it 'uma versão antiga, só com a instrução, restaura só a instrução' do
      # Arrange
      aplicar(rascunho, gerado('v1'))
      antiga = rascunho.instruction_versions.create!(account: account, instruction: 'instrucao antiga',
                                                     reason: 'kb_refresh',
                                                     instruction_hash: Digest::SHA256.hexdigest('instrucao antiga'))
      antes = retrato(rascunho)

      # Act
      rascunho.restore_instruction!(antiga)

      # Assert
      expect(retrato(rascunho)).to eq(antes.merge('instruction' => 'instrucao antiga'))
    end
  end
end
