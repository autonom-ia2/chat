require 'rails_helper'

# F3 do tema 8 (#1429): "Atualizar com a nova base" SÓ TROCA A BASE, com uma versão no histórico ("Base de seguros
# atualizada"), e o Desfazer volta à base de antes enquanto o agente não mudou de novo.
RSpec.describe Autonomia::Agents::TrocaDaBase do
  let(:conta) { conta_da_fase2 }
  let(:dono) { create(:user, account: conta, role: :administrator) }
  let(:antiga) { { 'segmento' => 'seguros/corretora', 'versao' => 'antiga000000', 'texto' => 'Texto antigo do ramo.' } }
  let(:nova) { { 'segmento' => 'seguros/corretora', 'versao' => 'nova00000000', 'texto' => 'Texto novo do ramo.' } }
  let(:agent) do
    criar_principal(conta, tone: 'cordial', greeting: 'Oi!', handoff_rule: 'Passe quando pedir.',
                           config: { 'with_knowledge' => false, 'guardrails' => ['Não invente.'], 'model' => 'x', 'base' => antiga })
  end

  def versoes
    agent.instruction_versions.order(:id)
  end

  describe '#trocar_base!' do
    it 'grava só a base nova; instrução, tom, saudação e o resto do config ficam iguais' do
      antes = agent.attributes.except('config', 'updated_at')
      config_antes = agent.config.except('base')

      agent.trocar_base!(nova, created_by: dono)

      agent.reload
      expect(agent.config['base']).to eq(nova)
      expect(agent.config.except('base')).to eq(config_antes)
      expect(agent.attributes.except('config', 'updated_at')).to eq(antes)
    end

    it 'grava o estado de antes e a versão "base_de_seguros", apontando para ele' do
      agent.trocar_base!(nova, created_by: dono)

      antes, aplicada = versoes.last(2)
      expect(antes.metadata.dig('agente', 'config', 'base')).to eq(antiga)
      expect(aplicada).to have_attributes(reason: 'base_de_seguros', created_by_id: dono.id)
      expect(aplicada.metadata['versao_antes_id']).to eq(antes.id)
      expect(aplicada.metadata.dig('agente', 'config', 'base')).to eq(nova)
    end

    it 'não duplica o estado de antes quando ele já é a última versão' do
      agent.record_instruction_version!(reason: 'manual_edit')

      expect { agent.trocar_base!(nova) }.to change(Autonomia::Agents::InstructionVersion, :count).by(1)
    end

    it 'com a mesma base já gravada, não faz nada' do
      agent.trocar_base!(antiga)

      expect(agent.reload.instruction_versions).to be_empty
    end

    it 'recusa a Lia' do
      lia = Autonomia::Agents::Agent.new(account: conta, agent_type: 'insurance_quote')

      expect { lia.trocar_base!(nova) }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
    end

    it 'recusa sem a Fase 2 ou sem instrução (não há versão para desfazer)' do
      sem_instrucao = criar_principal(conta, nome: 'Rascunho', instruction: nil)
      expect { sem_instrucao.trocar_base!(nova) }.to raise_error(described_class::TrocaIndisponivel)

      Autonomia::Agents::Fase2.desligar!(conta)
      expect { agent.reload.trocar_base!(nova) }.to raise_error(described_class::TrocaIndisponivel)
    end
  end

  describe '#desfazer_troca_da_base!' do
    it 'volta à base de antes, grava a volta e marca a troca como desfeita' do
      agent.trocar_base!(nova, created_by: dono)
      aplicada = versoes.last

      agent.desfazer_troca_da_base!(created_by: dono)

      expect(agent.reload.config['base']).to eq(antiga)
      volta = versoes.last
      expect(volta).to have_attributes(reason: 'rollback', created_by_id: dono.id)
      expect(volta.metadata).to include('voltou_para' => aplicada.metadata['versao_antes_id'], 'desfez_base' => aplicada.id)
      expect(aplicada.reload.metadata['desfeita']).to be(true)
      expect(agent.base_desfazivel).to be_nil
    end

    it 'agente que nasceu sem marca volta a ficar sem a chave base' do
      sem_marca = criar_principal(conta, nome: 'Sem marca')
      sem_marca.trocar_base!(nova)

      sem_marca.desfazer_troca_da_base!

      expect(sem_marca.reload.config).not_to have_key('base')
    end

    it 'depois de outra mudança no agente, não desfaz mais' do
      agent.trocar_base!(nova)
      agent.update!(tone: 'formal')

      expect(agent.base_desfazivel).to be_nil
      expect { agent.desfazer_troca_da_base! }.to raise_error(described_class::BaseMudou)
      expect(agent.reload.config['base']).to eq(nova)
    end

    it 'ligar ou desligar o agente não tira o Desfazer' do
      agent.trocar_base!(nova)
      agent.update!(enabled: false)

      expect(agent.base_desfazivel).to be_present
    end

    it 'sem troca de base, não há o que desfazer' do
      expect { agent.desfazer_troca_da_base! }.to raise_error(described_class::BaseMudou)
    end

    it 'a volta por Versões depois da troca também fecha o Desfazer' do
      agent.trocar_base!(nova)
      agent.restore_instruction!(versoes.first)

      expect(agent.reload.config['base']).to eq(antiga)
      expect(agent.base_desfazivel).to be_nil
    end
  end
end
