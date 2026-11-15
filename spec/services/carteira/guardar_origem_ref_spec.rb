require 'rails_helper'

# E7 (#2900) — a referência do registro na origem (`origem_ref`, o `ref` do conector): o gravador acha o seguro por ela
# antes do número, dá a referência ao seguro achado pelo número que ainda não tinha, e a referência vazia vira nula.
# E a conexão do Agger serve à conta que só tem a carteira. Tudo fictício.
RSpec.describe Carteira::Guardar, :aggregate_failures do
  let(:account) { conta_com_carteira }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo') }
  let(:dados) { { tipo: 'auto', seguradora: 'Seguradora Exemplo', numero: 'EX-000900', fim_vigencia: Date.new(2027, 3, 1) } }

  def guardar(dados_da_vez = dados, origem_ref: 'ref-exemplo-1')
    described_class.new(account, origem: 'conector').call(dados_da_vez, contato: pessoa, origem_ref: origem_ref)
  end

  it 'a mesma referência atualiza o mesmo seguro, mesmo com outro número' do
    primeiro = guardar
    segundo = guardar(dados.merge(numero: 'EX-000901', valor_centavos: 150_000))

    expect(segundo.apolice).to eq(primeiro.apolice)
    expect(segundo.situacao).to eq(described_class::ATUALIZADA)
    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(1)
    expect(primeiro.apolice.reload.origem_ref).to eq('ref-exemplo-1')
  end

  it 'o seguro achado pelo número que ainda não tinha referência passa a ter' do
    ja_estava = criar_apolice(pessoa, **dados, origem: 'planilha')

    expect(guardar.apolice).to eq(ja_estava)
    expect(ja_estava.reload).to have_attributes(origem_ref: 'ref-exemplo-1', origem: 'conector')
  end

  it 'a referência vazia vira nula, e não junta seguros diferentes' do
    um = guardar(origem_ref: '  ')
    outro = guardar(dados.merge(numero: 'EX-000902'), origem_ref: '')

    expect([um.apolice.origem_ref, outro.apolice.origem_ref]).to eq([nil, nil])
    expect(um.apolice).not_to eq(outro.apolice)
  end

  it 'a conexão do Agger é permitida à conta com a carteira, sem a Cotação' do
    expect(Autonomia::Insurance::Config.enabled?(account)).to be(false)
    expect(Autonomia::Insurance::Config.conexao_permitida?(account)).to be(true)
    expect(Autonomia::Insurance::Config.conexao_permitida?(create(:account))).to be(false)
  end
end
