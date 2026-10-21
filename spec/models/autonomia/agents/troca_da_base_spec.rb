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

    # A regra das versões da marca (#1802, lote 6): versão sem marca mantém a marca atual. O caminho de volta a "sem base"
    # é o Desfazer, que devolve a chave como estava.
    it 'a volta por Versões a antes da troca, num agente que nasceu sem marca, mantém a base atual' do
      sem_marca = criar_principal(conta, nome: 'Sem marca')
      sem_marca.trocar_base!(nova)

      sem_marca.restore_instruction!(sem_marca.instruction_versions.order(:id).first)

      expect(sem_marca.reload.config['base']).to eq(nova)
    end
  end

  describe '#retrato_para_comparar' do
    it 'é o mesmo no objeto em memória e relido do banco (a ordem das chaves do jsonb não conta)' do
      expect(agent.retrato_para_comparar).to eq(Autonomia::Agents::Agent.find(agent.id).retrato_para_comparar)
    end

    it 'não muda sozinho: ligar, desligar e o resultado do material não contam' do
      antes = agent.retrato_para_comparar

      agent.update!(enabled: false)
      Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste', { 'situacao' => 'ok' })

      expect(agent.reload.retrato_para_comparar).to eq(antes)
    end

    it 'muda com o que muda a resposta: o jeito de falar e a base' do
      antes = agent.retrato_para_comparar

      expect(agent.tap { |agente| agente.update!(tone: 'formal') }.retrato_para_comparar).not_to eq(antes)
      expect(agent.tap { |agente| agente.update_columns(config: agente.config.merge('base' => nova)) }.retrato_para_comparar) # rubocop:disable Rails/SkipsModelValidations
        .not_to eq(antes)
    end

    it 'a troca confere o retrato sob a trava: o agente salvo depois da conferência não é trocado' do
      retrato = agent.retrato_para_comparar
      Autonomia::Agents::Agent.where(id: agent.id).update_all(instruction: 'Salva no meio.') # rubocop:disable Rails/SkipsModelValidations

      expect { agent.trocar_base!(nova, retrato: retrato) }.to raise_error(described_class::RetratoMudou)
      expect(agent.reload.config['base']).to eq(antiga)
    end
  end

  describe 'save comum do agente durante a troca' do
    it 'um objeto lido antes da troca não regrava a base antiga ao salvar outra coisa' do
      lido_antes = Autonomia::Agents::Agent.find(agent.id)
      agent.trocar_base!(nova)

      lido_antes.update!(tone: 'formal', config: lido_antes.config.merge('voice' => 'grave'))

      expect(agent.reload.config['base']).to eq(nova)
      expect(agent.config['voice']).to eq('grave')
      expect(agent.tone).to eq('formal')
    end

    it 'um objeto lido antes da troca, num agente sem marca, não apaga a base nova' do
      sem_marca = criar_principal(conta, nome: 'Sem marca')
      lido_antes = Autonomia::Agents::Agent.find(sem_marca.id)
      sem_marca.trocar_base!(nova)

      lido_antes.update!(config: lido_antes.config.merge('voice' => 'grave'))

      expect(sem_marca.reload.config['base']).to eq(nova)
    end

    # A corrida espelhada: lido entre a troca e o Desfazer, salvo depois do Desfazer.
    it 'um objeto lido depois da troca e salvo depois do Desfazer não regrava a base nova' do
      agent.trocar_base!(nova)
      lido_no_meio = Autonomia::Agents::Agent.find(agent.id)
      agent.reload.desfazer_troca_da_base!

      lido_no_meio.update!(config: lido_no_meio.config.merge('voice' => 'grave'))

      expect(agent.reload.config['base']).to eq(antiga)
      expect(agent.config['voice']).to eq('grave')
    end

    it 'o mesmo num agente sem marca: o Desfazer tirou a chave, e o save não a devolve' do
      sem_marca = criar_principal(conta, nome: 'Sem marca')
      sem_marca.trocar_base!(nova)
      lido_no_meio = Autonomia::Agents::Agent.find(sem_marca.id)
      sem_marca.reload.desfazer_troca_da_base!

      lido_no_meio.update!(config: lido_no_meio.config.merge('voice' => 'grave'))

      expect(sem_marca.reload.config).not_to have_key('base')
    end
  end
end
