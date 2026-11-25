require 'rails_helper'

RSpec.describe Autonomia::Agents::PromptParts::Agora do
  def conta_no_fuso(fuso)
    create(:account, reporting_timezone: fuso)
  end

  it 'no fuso da conta' do
    travel_to Time.utc(2026, 11, 24, 17, 35) do
      expect(described_class.texto(conta_no_fuso('America/Sao_Paulo')))
        .to eq('Agora: terça-feira, 24/11/2026 14:35 (fuso da conta: America/Sao_Paulo).')
    end
  end

  it 'outro fuso' do
    travel_to Time.utc(2026, 11, 24, 17, 35) do
      expect(described_class.texto(conta_no_fuso('Europe/Lisbon')))
        .to eq('Agora: terça-feira, 24/11/2026 17:35 (fuso da conta: Europe/Lisbon).')
    end
  end

  it 'domingo e virada de dia pelo fuso' do
    travel_to Time.utc(2026, 11, 30, 2, 10) do
      expect(described_class.texto(conta_no_fuso('America/Sao_Paulo')))
        .to eq('Agora: domingo, 29/11/2026 23:10 (fuso da conta: America/Sao_Paulo).')
    end
  end

  it 'sem conta: o fuso padrão' do
    expect(described_class.texto(nil)).to include("(fuso da conta: #{Crm::Timezone::Resolver.default_timezone}).")
  end
end
