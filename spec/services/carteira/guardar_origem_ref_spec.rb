require 'rails_helper'

# E7 (#2900) — a referência do registro na origem (`origem_ref`, o `ref` do conector): o gravador acha o seguro por ela
# antes do número, se for do mesmo termo; a renovação que mantém a referência é outro termo e nasce outra apólice (que
# fica com a referência e se liga à anterior); o seguro achado pelo número que ainda não tinha referência passa a ter; a
# referência vazia vira nula. E a conexão do Agger serve à conta que só tem a carteira. Tudo fictício.
RSpec.describe Carteira::Guardar, :aggregate_failures do
  let(:account) { conta_com_carteira }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo') }
  let(:comeca) { Date.new(2026, 3, 1) }
  # Os dados chegam na forma do banco, com as chaves de comparação, como toda fonte entrega ao gravador.
  let(:dados) { dados_do_seguro('EX-000900', comeca) }

  def dados_do_seguro(numero, inicio)
    { tipo: 'auto', seguradora: 'Seguradora Exemplo', seguradora_chave: Carteira::Chave.seguradora('Seguradora Exemplo'),
      numero: numero, numero_chave: Carteira::Chave.numero(numero), inicio_vigencia: inicio, fim_vigencia: inicio + 1.year }
  end

  def guardar(dados_da_vez = dados, origem_ref: 'ref-exemplo-1')
    described_class.new(account, origem: 'conector').call(dados_da_vez, contato: pessoa, origem_ref: origem_ref)
  end

  it 'a mesma referência do mesmo termo atualiza o mesmo seguro, mesmo com outro número' do
    primeiro = guardar
    segundo = guardar(dados.merge(numero: 'EX-000901', numero_chave: Carteira::Chave.numero('EX-000901'), valor_centavos: 150_000))

    expect(segundo.apolice).to eq(primeiro.apolice)
    expect(segundo.situacao).to eq(described_class::ATUALIZADA)
    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(1)
    expect(primeiro.apolice.reload.origem_ref).to eq('ref-exemplo-1')
  end

  it 'a renovação com a mesma referência é outro termo: nasce outra apólice, que fica com a referência e se liga à anterior' do
    anterior = guardar.apolice
    renovacao = guardar(dados_do_seguro('EX-000900', comeca + 1.year))

    expect(renovacao.situacao).to eq(described_class::NOVA)
    expect(renovacao.apolice).not_to eq(anterior)
    expect([anterior.reload.origem_ref, renovacao.apolice.origem_ref]).to eq([nil, 'ref-exemplo-1'])
    expect(anterior.fim_vigencia).to eq(comeca + 1.year)

    expect(Carteira::Renovacao::Ligar.new(renovacao.apolice).sozinha).to eq(anterior)
    expect(anterior.reload.renovado_em).to be_present
  end

  it 'o termo velho que chega depois do novo, com a mesma referência, não toma a referência nem sobrescreve o novo' do
    novo = guardar(dados_do_seguro('EX-000900', comeca + 1.year)).apolice
    velho = guardar(dados)

    expect(velho.situacao).to eq(described_class::NOVA)
    expect([novo.reload.origem_ref, velho.apolice.origem_ref]).to eq(['ref-exemplo-1', nil])
    expect(novo.inicio_vigencia).to eq(comeca + 1.year)
    expect(guardar(dados).apolice).to eq(velho.apolice)
    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(2)
  end

  it 'o seguro achado pelo número que ainda não tinha referência passa a ter' do
    ja_estava = criar_apolice(pessoa, **dados.except(:seguradora_chave, :numero_chave), origem: 'planilha')

    expect(guardar.apolice).to eq(ja_estava)
    expect(ja_estava.reload).to have_attributes(origem_ref: 'ref-exemplo-1', origem: 'conector')
  end

  it 'a referência vazia vira nula, e não junta seguros diferentes' do
    um = guardar(origem_ref: '  ')
    outro = guardar(dados_do_seguro('EX-000902', comeca), origem_ref: '')

    expect([um.apolice.origem_ref, outro.apolice.origem_ref]).to eq([nil, nil])
    expect(um.apolice).not_to eq(outro.apolice)
  end

  it 'a conexão do Agger é permitida à conta com a carteira, sem a Cotação' do
    expect(Autonomia::Insurance::Config.enabled?(account)).to be(false)
    expect(Autonomia::Insurance::Config.conexao_permitida?(account)).to be(true)
    expect(Autonomia::Insurance::Config.conexao_permitida?(create(:account))).to be(false)
  end
end
