require 'rails_helper'

# Os esqueletos por tipo de agente moram em config/agentes_esqueletos (#1429, F1): o texto sai do builder.rb para ser
# revisado como texto, e o Construtor e o Revisor continuam lendo pelas mesmas constantes.
RSpec.describe Autonomia::Agents::Builder do
  let(:pasta) { Rails.root.join('config/agentes_esqueletos') }

  it 'tem um esqueleto para cada tipo, menos o personalizado' do
    expect(described_class::SKELETON_INSTRUCTIONS.keys).to match_array(%w[support sdr reception onboarding scheduler reactivation])
    expect(described_class.skeleton_for('custom')).to be_nil
  end

  it 'lê cada esqueleto do arquivo do tipo, sem mudar o texto' do
    described_class::SKELETON_INSTRUCTIONS.each do |tipo, texto|
      expect(texto).to eq(File.read(pasta.join("#{tipo}.md")))
      expect(texto).to be_frozen
    end
    expect(described_class::SCHEDULER_WITH_BOOKING_SKELETON).to eq(File.read(pasta.join('scheduler_com_agenda.md')))
  end

  it 'não deixa arquivo de esqueleto sem uso' do
    usados = described_class::SKELETON_INSTRUCTIONS.keys + ['scheduler_com_agenda']

    expect(Dir.children(pasta).map { |nome| File.basename(nome, '.md') }).to match_array(usados)
  end
end
