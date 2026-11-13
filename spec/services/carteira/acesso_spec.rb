require 'rails_helper'

# E4 (#2897): quem tem a carteira de seguros. A chave sozinha não basta: a conta precisa das telas novas de
# Relacionamentos e ser corretora de seguros.
RSpec.describe Carteira::Acesso do
  let(:account) { conta_com_carteira }

  def com_o_nicho(nicho, perfil)
    Autonomia::Agents::Nicho.atribuir(account, nicho: nicho, perfil: perfil)
    account.save!
    account
  end

  # Sem padrão de nicho na instalação, venha o que vier do ambiente de quem roda.
  around { |example| with_modified_env(AUTONOMIA_NICHO_PADRAO: nil) { example.run } }

  it 'libera a corretora de seguros com as duas chaves ligadas' do
    expect(described_class.liberada?(account)).to be(true)
  end

  it 'fecha com a chave da carteira desligada e fecha sem as telas novas de Relacionamentos' do
    fechadas = %w[carteira_seguros relacionamentos_novo].map do |chave|
      account.disable_features!(chave)
      fechada = described_class.liberada?(account)
      account.enable_features!(chave)
      fechada
    end

    expect(fechadas).to eq([false, false])
  end

  it 'fecha no nicho geral e nos outros perfis de seguros' do
    fora = [%w[geral], %w[seguros seguradora], %w[seguros insurtech], %w[seguros saude_beneficios]]

    expect(fora.map { |nicho, perfil| described_class.liberada?(com_o_nicho(nicho, perfil)) }).to all(be(false))
  end

  it 'fecha na conta que não escolheu nicho, mesmo com as chaves ligadas' do
    sem_escolha = create(:account).tap { |conta| conta.enable_features!(*described_class::CHAVES) }

    expect(described_class.liberada?(sem_escolha)).to be(false)
  end

  it 'não depende dos pacotes de tradução da stack: com eles desligados o painel não recebe pacote e a carteira continua' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') do
      expect([Autonomia::Segmentos::Pacotes.nome(account), described_class.liberada?(account)]).to eq([nil, true])
    end
  end
end
