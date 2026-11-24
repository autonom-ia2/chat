require 'rails_helper'

# #1426 (tema 4b) — as chaves do material no `config` do agente (conferências) são escritas pelo sistema, de forma
# atômica, e nenhum save do agente com o `config` lido antes as apaga (a corrida da conferência que termina enquanto a
# pessoa salva a gaveta).
RSpec.describe Autonomia::Agents::ConfigDoMaterial do
  include_context 'with material do agente'

  let(:resultado) { { 'hash_da_base' => 'h1', 'contradicoes' => [{ 'id' => 'c1', 'assunto' => 'Abre sábado?' }] } }

  it 'grava só a chave pedida, sem tocar no resto do config' do
    agent.update!(config: { 'voice' => 'feminina', 'guardrails' => ['Não invente.'] })

    described_class_gravar('conferencia_da_base', resultado)

    expect(agent.reload.config).to include('voice' => 'feminina', 'guardrails' => ['Não invente.'], 'conferencia_da_base' => resultado)
  end

  it 'a escrita do sistema não mexe no updated_at do agente (o Desfazer do #1428 o compara)' do
    antes = agent.reload.updated_at

    travel(1.minute) { described_class_gravar('conferencia_da_base', resultado) }

    expect(agent.reload.updated_at).to eq(antes)
  end

  it 'recusa chave que não é do material' do
    expect { Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'voice', 'x') }.to raise_error(ArgumentError)
  end

  describe 'a corrida com o save do agente' do
    it 'save com o config lido ANTES do resultado não apaga o resultado novo', :aggregate_failures do
      velho = Autonomia::Agents::Agent.find(agent.id)
      described_class_gravar('conferencia_da_base', resultado)

      velho.update!(config: velho.config.merge('voice' => 'masculina'))

      config = agent.reload.config
      expect(config['voice']).to eq('masculina')
      expect(config['conferencia_da_base']).to eq(resultado)
    end

    it 'save que tenta escrever a chave do material com valor velho fica com o salvo' do
      described_class_gravar('conferencia_da_base', { 'hash_da_base' => 'velho' })
      velho = Autonomia::Agents::Agent.find(agent.id)
      described_class_gravar('conferencia_da_base', resultado)

      velho.update!(config: velho.config.merge('voice' => 'masculina'))

      expect(agent.reload.config['conferencia_da_base']).to eq(resultado)
    end

    it 'save sem mudar o config não relê nada (e não trava a linha)' do
      described_class_gravar('conferencia_da_base', resultado)
      consultas = []
      callback = ->(*, payload) { consultas << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { agent.reload.update!(tone: 'cordial') }

      expect(consultas.select { |sql| sql.include?('FOR UPDATE') }).to be_empty
    end

    it 'fora da Fase 2 o save do agente fica o da main: sem leitura sob trava' do
      Autonomia::Agents::Fase2.desligar!(account)
      consultas = []
      callback = ->(*, payload) { consultas << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        agent.reload.update!(config: agent.config.merge('voice' => 'masculina'))
      end

      expect(consultas.select { |sql| sql.include?('FOR UPDATE') }).to be_empty
    end

    it 'save que muda o config lê as chaves do material sob a trava da linha, na transação do save' do
      consultas = []
      callback = ->(*, payload) { consultas << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        agent.update!(config: agent.config.merge('voice' => 'masculina'))
      end

      trava = consultas.index { |sql| sql.include?('FOR UPDATE') && sql.include?('autonomia_agents') }
      escrita = consultas.index { |sql| sql.start_with?('UPDATE "autonomia_agents"') }
      expect(trava).to be < escrita
    end
  end

  it 'alterar_chave_do_material! lê o valor salvo (não o do objeto em memória) e grava o que o bloco devolve' do
    velho = Autonomia::Agents::Agent.find(agent.id)
    described_class_gravar('conferencia_da_base', { 'feitas' => 3 })

    velho.alterar_chave_do_material!('conferencia_da_base') { |atual| atual.merge('feitas' => atual['feitas'] + 1) }

    expect(agent.reload.config['conferencia_da_base']).to eq({ 'feitas' => 4 })
  end

  it 'alterar_chave_do_material! com bloco que devolve nil não grava' do
    described_class_gravar('conferencia_da_base', resultado)

    agent.alterar_chave_do_material!('conferencia_da_base') { nil }

    expect(agent.reload.config['conferencia_da_base']).to eq(resultado)
  end

  def described_class_gravar(chave, valor)
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, chave, valor)
  end
end
