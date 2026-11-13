require 'rails_helper'

# E4 (#2897): o selo de seguro de cada pessoa de uma página da lista de pessoas. Tudo fictício.
RSpec.describe Carteira::ResumoPorPessoa do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }

  before { travel_to(agora) }

  def pessoa(nome, conta: account)
    create(:contact, account: conta, name: nome, contact_type: :customer)
  end

  def resumo(*pessoas)
    described_class.new(account, pessoas.map { |quem| quem.id.to_s }).call
  end

  it 'diz quantos seguros a pessoa tem e mostra o que mais pede atenção: vencido, depois o ativo que termina antes' do
    marina = pessoa('Marina Exemplo')
    criar_apolice(marina, tipo: 'vida', fim_vigencia: hoje + 300)
    criar_apolice(marina, tipo: 'auto', fim_vigencia: hoje + 18)
    bruno = pessoa('Bruno Exemplo')
    criar_apolice(bruno, tipo: 'residencial', fim_vigencia: hoje + 40)
    criar_apolice(bruno, tipo: 'auto', fim_vigencia: hoje - 3)
    criar_apolice(bruno, tipo: 'vida', fim_vigencia: hoje + 5, cancelado_em: agora - 1.day)

    expect(resumo(marina, bruno)).to eq(
      marina.id => { quantos: 2, selo: 'ativo', tipo: 'auto', dias: 18 },
      bruno.id => { quantos: 3, selo: 'vencido', tipo: 'auto', dias: -3 }
    )
  end

  it 'quem só tem seguro cancelado mostra o cancelado, e quem não tem seguro não vem' do
    carla = pessoa('Carla Exemplo')
    criar_apolice(carla, tipo: 'empresarial', fim_vigencia: hoje + 90, cancelado_em: agora - 2.days)

    expect(resumo(carla, pessoa('Sem Seguro'))).to eq(carla.id => { quantos: 1, selo: 'cancelado', tipo: 'empresarial', dias: 90 })
  end

  it 'às 22h da conta o seguro que vence hoje ainda está ativo, mesmo com o servidor no dia seguinte' do
    marina = pessoa('Marina Exemplo')
    criar_apolice(marina, fim_vigencia: hoje)
    travel_to(Time.utc(2026, 11, 13, 1))

    expect(resumo(marina).fetch(marina.id)).to include(selo: 'ativo', dias: 0)
  end

  it 'não lê seguro de outra conta, nem pelo id da pessoa de lá' do
    outra = conta_com_carteira
    de_fora = pessoa('Dona de fora', conta: outra)
    criar_apolice(de_fora, fim_vigencia: hoje + 10)

    expect(resumo(de_fora)).to eq({})
    expect(described_class.new(outra, [de_fora.id]).call.keys).to eq([de_fora.id])
  end

  it 'faz uma consulta só, seja uma pessoa ou a página inteira' do
    pessoas = Array.new(6) { |n| pessoa("Pessoa #{n}").tap { |dona| 2.times { criar_apolice(dona, fim_vigencia: hoje + n + 1) } } }
    uma = described_class.new(account, [pessoas.first.id])
    todas = described_class.new(account, pessoas.map(&:id))

    expect([consultas_da_carteira { uma.call }, consultas_da_carteira { todas.call }]).to eq([1, 1])
    expect(todas.call.size).to eq(6)
  end

  it 'recusa o pedido sem ids, com ids demais ou com id que não é de ninguém, sem repetir o que foi mandado' do
    alem_do_teto = Array.new(described_class::LIMITE + 1) { |n| (n + 1).to_s }
    recusados = [nil, '7', [], alem_do_teto, ['abc'], ['0'], ['-4'], ['12abc'], [(described_class::MAIOR_ID + 1).to_s], [{ 'id' => '7' }]]

    respostas = recusados.map do |pedido|
      described_class.new(account, pedido)
      'aceito'
    rescue Relacionamentos::PedidoInvalido => e
      e.message
    end

    expect(respostas).to eq((['pessoa_ids em formato inválido'] * 4) + (['pessoa_ids com id inválido'] * 6))
  end

  it 'aceita até o teto de ids' do
    no_teto = Array.new(described_class::LIMITE) { |n| (n + 1).to_s }

    expect(described_class.new(account, no_teto).call).to eq({})
  end
end
