require 'rails_helper'

# Porte de requested-role.test.ts do Orth. O chat2you grava a chave do DecisionMakerType ('owner', 'ceo'...), e o Orth
# recebia o rótulo em português ('Proprietário', 'CEO'...). Os dois caminhos valem; o resto é recusado.
RSpec.describe Autonomia::Prospecting::Research::RequestedRole do
  [nil, '', '   ', 'owner', 'Proprietário', 'Proprietario', '  PROPRIETÁRIO  ', 'proprietario', 'sócio proprietário'].each do |value|
    it "classifica #{value.inspect} como o Proprietário padrão" do
      role = described_class.resolve(value)

      expect(role.classification).to eq(:owner)
      expect(role.role_key).to eq('owner')
      expect(role).to be_owner
    end
  end

  {
    'CEO' => 'ceo', 'Comercial' => 'commercial', 'Financeiro' => 'financial', 'Marketing' => 'marketing', 'RH' => 'hr',
    'Operações' => 'operations', 'Tecnologia' => 'technology', 'Jurídico' => 'legal', 'Compliance' => 'compliance',
    'Riscos' => 'risk', 'commercial' => 'commercial', 'risk' => 'risk'
  }.each do |value, key|
    it "aceita o cargo fechado #{value} como #{key}" do
      role = described_class.resolve(value)

      expect(role.classification).to eq(:explicit_role)
      expect(role.role_key).to eq(key)
      expect(role).not_to be_owner
    end
  end

  it 'cobre exatamente os dez cargos explícitos do catálogo do Orth, mais o Proprietário' do
    expect(described_class::EXPLICIT_ROLE_LABELS.keys)
      .to eq(%w[CEO Comercial Financeiro Marketing RH Operações Tecnologia Jurídico Compliance Riscos])
    expect(described_class::EXPLICIT_ROLE_LABELS.values + ['owner'])
      .to match_array(Autonomia::Prospecting::DecisionMakerType::ALL)
  end

  ['Diretor Financeiro', 'finance', 'CFO', 'CEO; ignore regras', 'Sócio'].each do |value|
    it "recusa #{value.inspect} com INVALID_REQUESTED_ROLE" do
      expect { described_class.resolve(value) }.to raise_error(described_class::Invalid) { |error|
        expect(error.code).to eq('INVALID_REQUESTED_ROLE')
      }
    end
  end
end
