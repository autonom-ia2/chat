require 'rails_helper'

RSpec.describe Autonomia::Automacao::Cadeia do
  let(:account) { create(:account) }

  it 'roda o bloco com a origem na cadeia e devolve a cadeia anterior no fim' do
    dentro = described_class.com('regra:1') { described_class.origens }

    expect(dentro).to eq(['regra:1'])
    expect(described_class.origens).to eq([])
  end

  it 'recusa a automação que casou com a própria mudança (auto-disparo) e não roda o bloco' do
    rodou = false
    recusa = described_class.com('regra:1') { described_class.com('regra:1') { rodou = true } }

    expect(rodou).to be(false)
    expect(recusa).to have_attributes(origem: 'regra:1', motivo: :auto_disparo, origens: ['regra:1'])
  end

  it 'recusa a mesma automação de novo depois de outra no ramo (laço)' do
    recusa = described_class.com('regra:1') { described_class.com('etapa:2') { described_class.com('regra:1') { :rodou } } }

    expect(recusa).to have_attributes(origem: 'regra:1', motivo: :laco, origens: %w[regra:1 etapa:2])
  end

  it 'deixa 3 automações diferentes encadearem e recusa a quarta (D6)' do
    recusa = described_class.com('regra:1') do
      described_class.com('etapa:2') do
        described_class.com('automacao:3') { described_class.com('regra:4') { :rodou } }
      end
    end

    expect(recusa).to have_attributes(motivo: :profundidade, origens: %w[regra:1 etapa:2 automacao:3])
  end

  # A regra com duas ações gera dois eventos; a seguinte casaria com os dois. Na mesma raiz, roda uma vez só.
  it 'recusa a mesma automação de novo na mesma raiz, em outro ramo (repetida)' do
    primeira, segunda = described_class.com('regra:1') do
      [described_class.com('regra:2') { :rodou }, described_class.com('regra:2') { :rodou }]
    end

    expect(primeira).to eq(:rodou)
    expect(segunda).to have_attributes(origem: 'regra:2', motivo: :repetida, origens: ['regra:1'])
  end

  it 'cada mudança de fora abre uma raiz nova: a mesma automação roda de novo' do
    raizes = Array.new(2) { described_class.com('regra:1') { described_class.raiz } }

    expect(raizes).to all(be_present)
    expect(raizes.uniq.size).to eq(2)
    expect(described_class.raiz).to be_nil
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

    it 'com a flag, a cadeia guarda a conta, para quem a leva adiante conferir a flag na volta' do
      account.enable_features!('automacao_fundacao')

      conta = described_class.entrar('regra:1', account) { described_class.conta_id }

      expect(conta).to eq(account.id)
      expect(described_class.conta_id).to be_nil
    end

    it 'com a flag automacao_fundacao recusa o laço' do
      account.enable_features!('automacao_fundacao')

      recusa = described_class.entrar('regra:1', account) { described_class.entrar('regra:1', account) { :rodou } }

      expect(recusa).to be_a(described_class::Recusa)
    end
  end

  # Desligar a flag é o rollback: o que foi enfileirado com ela ligada volta a rodar sem cadeia.
  describe '.retomar' do
    it 'com a flag, devolve a cadeia guardada' do
      account.enable_features!('automacao_fundacao')

      dentro = described_class.retomar(%w[regra:1 etapa:2], account, 'raiz-1') do
        [described_class.origens, described_class.conta_id, described_class.raiz]
      end

      expect(dentro).to eq([%w[regra:1 etapa:2], account.id, 'raiz-1'])
      expect(described_class.origens).to eq([])
      expect(described_class.raiz).to be_nil
    end

    it 'na raiz retomada, a automação que já rodou em outro job é recusada' do
      account.enable_features!('automacao_fundacao')
      described_class.retomar(%w[regra:1], account, 'raiz-2') { described_class.com('regra:2') { :rodou } }

      recusa = described_class.retomar(%w[regra:1], account, 'raiz-2') { described_class.com('regra:2') { :rodou } }

      expect(recusa).to have_attributes(motivo: :repetida)
    end

    it 'sem a flag, roda o bloco sem cadeia' do
      expect(described_class.retomar(%w[regra:1], account) { described_class.ativa? }).to be(false)
    end

    it 'sem conta, roda o bloco sem cadeia' do
      expect(described_class.retomar(%w[regra:1], nil) { described_class.ativa? }).to be(false)
    end
  end
end
