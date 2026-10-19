require 'rails_helper'

# #1426 (tema 4b) — as chaves do material no `config` do agente (conferências e autoteste) são escritas pelo sistema, de
# forma atômica, e nenhum save do agente com o `config` lido antes as apaga (a corrida do autoteste que termina enquanto
# a pessoa salva a gaveta).
RSpec.describe Autonomia::Agents::ConfigDoMaterial do
  include_context 'with material do agente'

  let(:resultado) { { 'rodada' => 'r1', 'estado' => 'pronto', 'itens' => [{ 'pergunta' => 'Abre sábado?' }] } }

  it 'grava só a chave pedida, sem tocar no resto do config' do
    agent.update!(config: { 'voice' => 'feminina', 'guardrails' => ['Não invente.'] })

    described_class_gravar('autoteste', resultado)

    expect(agent.reload.config).to include('voice' => 'feminina', 'guardrails' => ['Não invente.'], 'autoteste' => resultado)
  end

  it 'a escrita do sistema não mexe no updated_at do agente (o Desfazer do #1428 o compara)' do
    antes = agent.reload.updated_at

    travel(1.minute) { described_class_gravar('autoteste', resultado) }

    expect(agent.reload.updated_at).to eq(antes)
  end

  it 'recusa chave que não é do material' do
    expect { Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'voice', 'x') }.to raise_error(ArgumentError)
  end

  describe 'a corrida com o save do agente' do
    it 'save com o config lido ANTES do resultado não apaga o resultado novo', :aggregate_failures do
      velho = Autonomia::Agents::Agent.find(agent.id)
      described_class_gravar('autoteste', resultado)
      described_class_gravar('conferencia_da_base', { 'contradicoes' => [] })

      velho.update!(config: velho.config.merge('voice' => 'masculina'))

      config = agent.reload.config
      expect(config['voice']).to eq('masculina')
      expect(config['autoteste']).to eq(resultado)
      expect(config['conferencia_da_base']).to eq({ 'contradicoes' => [] })
    end

    it 'save que tenta escrever a chave do material com valor velho fica com o salvo' do
      described_class_gravar('autoteste', { 'rodada' => 'velha' })
      velho = Autonomia::Agents::Agent.find(agent.id)
      described_class_gravar('autoteste', resultado)

      velho.update!(config: velho.config.merge('voice' => 'masculina'))

      expect(agent.reload.config['autoteste']).to eq(resultado)
    end

    it 'save sem mudar o config não relê nada (e não trava a linha)' do
      described_class_gravar('autoteste', resultado)
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
    described_class_gravar('autoteste', { 'feitas' => 3 })

    velho.alterar_chave_do_material!('autoteste') { |atual| atual.merge('feitas' => atual['feitas'] + 1) }

    expect(agent.reload.config['autoteste']).to eq({ 'feitas' => 4 })
  end

  it 'alterar_chave_do_material! com bloco que devolve nil não grava' do
    described_class_gravar('autoteste', resultado)

    agent.alterar_chave_do_material!('autoteste') { nil }

    expect(agent.reload.config['autoteste']).to eq(resultado)
  end

  def described_class_gravar(chave, valor)
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, chave, valor)
  end
end
