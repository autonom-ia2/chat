require 'rails_helper'

# E6 (#2899): o texto da página em pedaços inteiros, para a conferência de valor. Dados fictícios.
RSpec.describe Carteira::Leitor::Tokens do
  subject(:tokens) { described_class.new(texto) }

  let(:texto) do
    "Apólice: EX-2026.001234. Segurada: Ana Lúcia (CPF: 123.456.789-00)\n" \
      "Tel.: (11) 99999-0001 | e-mail: ana.lucia@\nexemplo.invalid\n" \
      'Prêmio: R$ 1.234,56; parcela de R$ 205,76. Importância: R$ 80.000 Vigência: 12/11/2026'
  end

  it 'palavras: letras e dígitos seguidos, sem acento e em minúsculas; todo o resto separa' do
    expect(tokens.palavras.first(8)).to eq(%w[apolice ex 2026 001234 segurada ana lucia cpf])
  end

  it 'blocos: o que está escrito junto, com a pontuação de dentro e sem a das pontas' do
    expect(tokens.blocos).to include('ex-2026.001234', '123.456.789-00', '11', '99999-0001', 'e-mail', '1.234,56', '205,76', '80.000', '12/11/2026')
    expect(tokens.blocos).not_to include('ex-2026.001234.', 'tel.', '(11)', 'r$')
  end

  it 'códigos: cada bloco só com letra e dígito' do
    expect(tokens.codigos).to include('ex2026001234', '12345678900', '999990001')
  end

  it 'números: os dígitos do bloco que só tem número, na ordem dos blocos, e nil no bloco que tem letra ou vírgula' do
    expect(tokens.numeros.compact).to eq(%w[12345678900 11 999990001 80000 12112026])
    expect(tokens.numeros.size).to eq(tokens.blocos.size)
  end

  it 'números seguidos: os dígitos escritos em blocos de número vizinhos, do começo de um bloco ao fim de outro' do
    expect(%w[11999990001 999990001 12345678900].map { |digitos| tokens.numeros_seguidos?(digitos) }).to all(be(true))
    # Um pedaço de bloco, blocos com outra coisa no meio, e o vazio.
    expect(['1199999', '90001', '1234567890011', '8000012112026', '', nil].map { |digitos| tokens.numeros_seguidos?(digitos) }).to all(be(false))
  end

  it 'centavos: só o valor em dinheiro escrito com os centavos, por inteiro' do
    expect(tokens.centavos).to eq([123_456, 20_576])
  end

  it 'blocos emendados: só a quebra de linha junta dois pedaços' do
    expect(tokens.blocos).not_to include('ana.lucia@exemplo.invalid')
    expect(tokens.blocos_emendados).to include('ana.lucia@exemplo.invalid')
    expect(tokens.blocos_emendados).not_to include('99999-0001e-mail')
  end

  it 'sequência: o trecho inteiro e seguido dentro da lista' do
    lista = %w[seguradora exemplo s a apolice]

    expect([%w[exemplo s a], %w[seguradora], lista].map { |trecho| described_class.sequencia?(lista, trecho) }).to all(be(true))
    fora = [%w[seguradora s], %w[a s], %w[exemplos], [], lista + %w[mais]]
    expect(fora.map { |trecho| described_class.sequencia?(lista, trecho) }).to all(be(false))
  end

  it 'texto vazio ou só com pontuação não tem pedaço nenhum' do
    [nil, '', " \n ", '- / . ,'].each do |vazio|
      sem_nada = described_class.new(vazio)

      expect([sem_nada.palavras, sem_nada.blocos, sem_nada.codigos, sem_nada.numeros, sem_nada.centavos, sem_nada.blocos_emendados]).to all(eq([]))
    end
  end
end
