require 'rails_helper'

# Roteiros por segmento (#1429, F2; decisão do Rodrigo de 30/10): o esqueleto que o Construtor adapta vem da camada
# mais específica do pacote da conta que tiver o arquivo (seguros/<tipo> → seguros → geral), em
# config/agentes_por_pacote/<camada>/esqueletos/<tipo_de_agente>.md. Só para agente nascendo, com a Fase 2 ligada; o
# Revisor usa a camada gravada na marca do agente. Nada disso cria versão nova da base.
RSpec.describe Autonomia::Agents::Builder do
  let(:por_camada) do
    { 'seguros' => { 'support' => "ESQUELETO SEGUROS SUPPORT\n" },
      'seguros/saude_beneficios' => { 'support' => "ESQUELETO SAÚDE SUPPORT\n", 'sdr' => "ESQUELETO SAÚDE SDR\n" } }
  end

  before { stub_const("#{described_class}::SKELETONS_BY_LAYER", por_camada) }

  describe '.skeleton_for' do
    it 'usa a camada mais específica que tem o arquivo do tipo' do
      expect(described_class.skeleton_for('support', camadas: %w[seguros seguros/saude_beneficios])).to eq("ESQUELETO SAÚDE SUPPORT\n")
      expect(described_class.skeleton_for('sdr', camadas: %w[seguros seguros/saude_beneficios])).to eq("ESQUELETO SAÚDE SDR\n")
    end

    it 'cai na camada seguros e depois no geral quando o tipo não tem arquivo próprio' do
      expect(described_class.skeleton_for('support', camadas: %w[seguros seguros/corretora])).to eq("ESQUELETO SEGUROS SUPPORT\n")
      expect(described_class.skeleton_for('sdr', camadas: %w[seguros seguros/corretora]))
        .to eq(described_class::SKELETON_INSTRUCTIONS['sdr'])
    end

    it 'fica no geral sem camadas e sem esqueleto para o personalizado' do
      expect(described_class.skeleton_for('support')).to eq(described_class::SKELETON_INSTRUCTIONS['support'])
      expect(described_class.skeleton_for('custom', camadas: %w[seguros])).to be_nil
    end
  end

  describe 'contexto do esqueleto na criação' do
    let(:account) { create(:account) }
    let(:thread) { Autonomia::Agents::BuildThread.create!(account: account) }

    around { |example| with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { example.run } }

    before do
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(
        Autonomia::Agents::Nicho::NICHO_KEY => 'seguros', Autonomia::Agents::Nicho::PERFIL_KEY => 'saude_beneficios'
      ))
      thread.persist_start_options!(type: 'support', with_knowledge: false)
      thread.save!
    end

    def contexto
      described_class.new(account: account, build_thread: thread).send(:skeleton_context)
    end

    it 'usa o roteiro do tipo da conta com a Fase 2 ligada' do
      allow(Autonomia::Agents::Fase2).to receive(:ligada?).with(account).and_return(true)

      expect(contexto).to include('ESQUELETO SAÚDE SUPPORT')
    end

    it 'fica no esqueleto geral com a Fase 2 desligada' do
      allow(Autonomia::Agents::Fase2).to receive(:ligada?).with(account).and_return(false)

      expect(contexto).to include(described_class::SKELETON_INSTRUCTIONS['support'])
    end
  end

  describe 'escopo esperado no Revisor' do
    let(:account) { create(:account) }

    def dica(base)
      agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', config: { 'base' => base }.compact)
      fonte = instance_double(Autonomia::Agents::Source, agent: agente, account: account)
      Autonomia::Agents::Knowledge::Reviewer.new(source: fonte, token: 't').send(:type_scope_hint)
    end

    it 'usa o roteiro da camada gravada na marca do agente' do
      expect(dica({ 'segmento' => 'seguros/saude_beneficios' })).to include('ESQUELETO SAÚDE SUPPORT')
    end

    it 'usa o geral para agente sem marca' do
      expect(dica(nil)).to include(described_class::SKELETON_INSTRUCTIONS['support'])
    end
  end

  describe 'arquivos de roteiro' do
    it 'só tem roteiro de tipo de agente que existe, em camada de pacote que existe' do
      tipos = described_class::SKELETON_INSTRUCTIONS.keys
      camadas = ['seguros'] + Autonomia::Agents::Nicho::PERFIS.map { |perfil| "seguros/#{perfil}" }
      reais = Dir.glob(Rails.root.join('config/agentes_por_pacote/**/esqueletos/*.md'))

      reais.each do |arquivo|
        caminho = Pathname(arquivo).relative_path_from(Rails.root.join('config/agentes_por_pacote'))
        expect(camadas).to include(caminho.dirname.dirname.to_s)
        expect(tipos).to include(caminho.basename('.md').to_s)
      end
    end
  end
end
