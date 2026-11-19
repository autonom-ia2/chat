require 'rails_helper'

# E4 (#2897): quem tem a carteira de seguros. Desde a E9 (#2902) não há chave: as flags `carteira_seguros` e
# `relacionamentos_novo` saíram do código. Desde o #3053 (19/11) é toda conta do nicho seguros, de qualquer perfil.
RSpec.describe Carteira::Acesso do
  let(:account) { conta_com_carteira }

  def com_o_nicho(nicho, perfil)
    Autonomia::Agents::Nicho.atribuir(account, nicho: nicho, perfil: perfil)
    account.save!
    account
  end

  # Sem padrão de nicho na instalação, venha o que vier do ambiente de quem roda.
  around { |example| with_modified_env(AUTONOMIA_NICHO_PADRAO: nil) { example.run } }

  it 'libera a corretora de seguros' do
    expect(described_class.liberada?(account)).to be(true)
  end

  it 'libera os outros perfis de seguros: seguradora, insurtech e saúde e benefícios' do
    perfis = %w[seguradora insurtech saude_beneficios]

    expect(perfis.map { |perfil| described_class.liberada?(com_o_nicho('seguros', perfil)) }).to all(be(true))
  end

  it 'fecha na conta que saiu do nicho seguros' do
    sem_a_carteira!(account)

    expect(described_class.liberada?(account)).to be(false)
  end

  it 'não lê mais as flags antigas: a corretora com as duas desligadas continua com a carteira' do
    account.disable_features!('carteira_seguros', 'relacionamentos_novo')

    expect(described_class.liberada?(account.reload)).to be(true)
  end

  it 'fecha no nicho geral' do
    expect(described_class.liberada?(com_o_nicho('geral', nil))).to be(false)
  end

  it 'fecha na conta que não escolheu nicho, mesmo com a flag antiga ligada' do
    sem_escolha = create(:account).tap { |conta| conta.enable_features!('carteira_seguros') }

    expect(described_class.liberada?(sem_escolha)).to be(false)
  end

  it 'não depende dos pacotes de tradução da stack: com eles desligados o painel não recebe pacote e a carteira continua' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') do
      expect([Autonomia::Segmentos::Pacotes.nome(account), described_class.liberada?(account)]).to eq([nil, true])
    end
  end
end
