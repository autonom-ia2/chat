require 'rails_helper'

# O botão de UM registro só leva a um id que uma leitura deste turno trouxe
# (#590). `leu?` confere contra o TEXTO que a leitura devolve, então este
# arquivo lê pela `Consulta` de verdade: se o formato da leitura mudar, falha
# aqui, e não calado em produção.
RSpec.describe Autonomia::Guide::Contexto do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:contexto) { described_class.new(account: conta, user: admin) }
  let!(:caixa) { create_crm_inbox(account: conta, name: 'Sinistros', members: [admin]) }

  def ler_caixas(campos: nil)
    contexto.lido(contexto.consulta.ler('inboxes', {}, {}, campos: campos, teto: 6_000))
  end

  it 'reconhece o id que a leitura trouxe, com poucos campos ou com o registro inteiro', :aggregate_failures do
    ler_caixas(campos: %w[id name])
    expect(contexto.leu?(caixa.id)).to be(true)

    completo = described_class.new(account: conta, user: admin)
    completo.lido(completo.consulta.ler('inboxes', {}, {}, teto: 6_000))
    expect(completo.leu?(caixa.id.to_s)).to be(true)
  end

  # O 5 não pode passar porque a leitura trouxe o 55. O texto segue o formato
  # que o teste acima prova ser o da leitura de verdade.
  it 'não confunde um id com outro que começa pelos mesmos dígitos', :aggregate_failures do
    contexto.lido('[{"id":55,"name":"Comercial"},{"id":"77","name":"Vendas"}]')

    expect(contexto.leu?(5)).to be(false)
    expect(contexto.leu?(7)).to be(false)
    expect(contexto.leu?(55)).to be(true)
    expect(contexto.leu?('77')).to be(true)
  end

  it 'não reconhece nada antes de ler' do
    expect(contexto.leu?(caixa.id)).to be(false)
  end
end
