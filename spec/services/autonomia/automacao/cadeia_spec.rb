require 'rails_helper'

RSpec.describe Autonomia::Automacao::Cadeia do
  let(:account) { create(:account) }

  it 'roda o bloco com a origem na cadeia e devolve a cadeia anterior no fim' do
    dentro = described_class.com('regra:1') { described_class.origens }

    expect(dentro).to eq(['regra:1'])
    expect(described_class.origens).to eq([])
  end

  it 'recusa a mesma automação de novo na sequência (laço) e não roda o bloco' do
    rodou = false
    recusa = described_class.com('regra:1') { described_class.com('regra:1') { rodou = true } }

    expect(rodou).to be(false)
    expect(recusa).to have_attributes(origem: 'regra:1', motivo: :laco, origens: ['regra:1'])
  end

  it 'deixa 3 automações diferentes encadearem e recusa a quarta (D6)' do
    recusa = described_class.com('regra:1') do
      described_class.com('etapa:2') do
        described_class.com('automacao:3') { described_class.com('regra:4') { :rodou } }
      end
    end

    expect(recusa).to have_attributes(motivo: :profundidade, origens: %w[regra:1 etapa:2 automacao:3])
  end

  # O ActionService das regras e o tratador de exceção dos controllers zeram o Current no meio da sequência.
  it 'não se perde com Current.reset' do
    origens = described_class.com('regra:1') do
      Current.reset
      described_class.origens
    end

    expect(origens).to eq(['regra:1'])
  end

  it 'restaura a cadeia mesmo quando o bloco levanta' do
    expect { described_class.restaurada(['regra:9']) { raise 'falhou' } }.to raise_error('falhou')
    expect(described_class.origens).to eq([])
  end

  describe '.entrar' do
    it 'sem a flag não entra na cadeia: roda o bloco como antes da F1, sem anotar nada' do
      rodou = described_class.entrar('regra:1', account) { described_class.entrar('regra:1', account) { described_class.origens } }

      expect(rodou).to eq([])
    end

    it 'com a flag automacao_fundacao recusa o laço' do
      account.enable_features!('automacao_fundacao')

      recusa = described_class.entrar('regra:1', account) { described_class.entrar('regra:1', account) { :rodou } }

      expect(recusa).to be_a(described_class::Recusa)
    end
  end
end
