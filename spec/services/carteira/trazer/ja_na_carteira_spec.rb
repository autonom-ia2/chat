require 'rails_helper'

# E4 (#2897): o seguro da linha que já está na carteira de um jeito que o gravador recusaria vira problema da linha na
# leitura, em vez de falha calada na gravação. As linhas são as do validador (só os campos que contam). Dados fictícios.
RSpec.describe Carteira::Trazer::JaNaCarteira, :aggregate_failures do
  let(:account) { create(:account) }
  let(:ana) { create(:contact, account: account, phone_number: '+5511987650001', email: 'ana.albuquerino@exemplo.com.br') }
  let(:comeca) { Date.new(2026, 3, 10) }
  let(:termina) { Date.new(2027, 3, 10) }
  let(:colunas) do
    Carteira::Trazer::ColunasDeSeguro.new(
      'seguro_numero' => 'Apólice', 'seguro_seguradora' => 'Seguradora', 'seguro_tipo' => 'Ramo', 'seguro_termina' => 'Fim',
      'seguro_comeca' => 'Início'
    )
  end
  let(:seguro) do
    { 'Apólice' => 'EX-001234', 'Seguradora' => 'Seguradora Exemplo', 'Ramo' => 'Automóvel', 'Início' => '10/03/2026', 'Fim' => '10/03/2027' }
  end
  let!(:guardada) do
    criar_apolice(ana, seguradora: 'Seguradora Exemplo', numero: 'EX-001234', inicio_vigencia: comeca, fim_vigencia: termina)
  end

  def linha(numero, mudou = {}, telefone: '+5511987650001', email: nil, erros: [])
    { row_number: numero, normalized_phone: telefone, email: email, extra_values: seguro.merge(mudou), errors: erros }
  end

  # [quantas linhas boas são de apólice cancelada, os motivos de cada linha].
  def marcar(*linhas)
    [described_class.new(account, colunas).marcar(linhas), linhas.pluck(:errors)]
  end

  it 'a apólice guardada da mesma pessoa (pelo telefone, ou pelo e-mail sem diferença de maiúscula) não é problema' do
    pelo_email = linha(3, { 'Apólice' => 'ex 001234' }, telefone: nil, email: 'Ana.Albuquerino@exemplo.com.br')

    expect(marcar(linha(2), pelo_email)).to eq([0, [[], []]])
  end

  it 'a apólice guardada em nome de outra pessoa vira problema da linha: nada muda de dono' do
    de_outra = linha(2, telefone: '+5511987650003', email: 'carla.carvalhedo@exemplo.com.br')

    expect(marcar(de_outra, linha(3, telefone: nil, email: nil))).to eq([0, [%w[seguro_de_outra_pessoa], %w[seguro_de_outra_pessoa]]])
  end

  it 'a apólice que a conta não tem, e o termo novo de uma que ela tem, não são problema' do
    nova = linha(2, { 'Apólice' => 'EX-005678' }, telefone: '+5511987650003')
    renovada = linha(3, { 'Início' => '10/03/2027', 'Fim' => '10/03/2028' })

    expect(marcar(nova, renovada)).to eq([0, [[], []]])
  end

  it 'com dois termos guardados de mesmo começo e nenhum igual ao da linha, a linha vira problema: o sistema não adivinha' do
    criar_apolice(ana, seguradora: 'Seguradora Exemplo', numero: 'EX-001234', inicio_vigencia: comeca, fim_vigencia: termina + 3.months)

    expect(marcar(linha(2, { 'Fim' => '10/09/2027' }), linha(3))).to eq([0, [%w[seguro_termo_ambiguo], []]])
  end

  it 'a apólice cancelada na carteira não é problema: a linha é contada, para a conferência dizer' do
    guardada.update!(cancelado_em: Time.current)

    expect(marcar(linha(2), linha(3, { 'Apólice' => 'EX-005678' }))).to eq([1, [[], []]])
  end

  it 'não olha a linha que já tinha problema, nem a apólice de outra conta' do
    de_fora = create(:contact, account: create(:account), phone_number: '+5511987650009')
    criar_apolice(de_fora, seguradora: 'Seguradora Exemplo', numero: 'EX-009999', inicio_vigencia: comeca, fim_vigencia: termina)
    com_problema = linha(2, telefone: '+5511987650003', erros: ['seguro_valor_invalido'])

    expect(marcar(com_problema, linha(3, { 'Apólice' => 'EX-009999' }))).to eq([0, [%w[seguro_valor_invalido], []]])
  end
end
