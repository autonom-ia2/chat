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
    expect(tokens.blocos).to include('ex-2026.001234', '123.456.789-00', '11', '99999-0001', 'e-mail', 'r$', '1.234,56', '205,76', '80.000',
                                     '12/11/2026')
    expect(tokens.blocos).not_to include('ex-2026.001234.', 'tel.', '(11)', 'r')
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
    expect(tokens.centavos_com_cifrao).to eq([123_456, 20_576])
  end

  # Segunda revisão, alto 2: "7,38%" virava 738 centavos e "1.250,50 kg" saía como valor certo.
  describe 'o que não é dinheiro, e o que é dinheiro sem "R$"' do
    subject(:tokens) do
      described_class.new('IOF de 7,38% sobre R$ 2.100,00. Peso 1.250,50 kg. Total R$2.254,98 ou 2.254,98. Taxa 0,38 % e % 1,00')
    end

    it 'o bloco encostado em "%", colado ou com espaço, antes ou depois, nunca é dinheiro' do
      expect(tokens.blocos).to include('7,38%', '%')
      expect(tokens.centavos & [738, 38, 100]).to eq([])
    end

    it 'o valor logo depois de "R$", com ou sem espaço, é o único que sai com cifrão; o solto e o de outra medida, não' do
      expect(tokens.centavos).to eq([210_000, 125_050, 225_498, 225_498])
      expect(tokens.centavos_com_cifrao).to eq([210_000, 225_498])
    end
  end

  it 'o inspect e o JSON não mostram o texto' do
    expect(tokens.inspect).to eq("#<Carteira::Leitor::Tokens blocos=#{tokens.blocos.size}>")
    expect(tokens.to_json).to eq('{"classe":"Carteira::Leitor::Tokens"}')
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

      expect([sem_nada.palavras, sem_nada.blocos, sem_nada.numeros, sem_nada.centavos, sem_nada.centavos_com_cifrao,
              sem_nada.blocos_emendados]).to all(eq([]))
    end
  end
end
