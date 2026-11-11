# CPF VÁLIDO (#2858, F1): confere se o número de um CPF é válido (os dois dígitos verificadores) e diz a região fiscal
# em que ele foi emitido (o nono dígito). Tudo calculado aqui (`cpf/calculo.rb`): nenhuma chamada externa, nenhum nome,
# nenhuma situação na Receita. Por ser dado pessoal, não passa pelo cache (`validade: nil`) e o número nunca volta na
# resposta, no log ou no contador.
module Autonomia::FerramentasProntas::Fontes::Cpf
  Parametro = Autonomia::FerramentasProntas::Parametro

  # O nono dígito do CPF é a região fiscal de emissão (Receita Federal).
  REGIOES = {
    '0' => %w[RS], '1' => %w[DF GO MS MT TO], '2' => %w[AC AM AP PA RO RR], '3' => %w[CE MA PI],
    '4' => %w[AL PB PE RN], '5' => %w[BA SE], '6' => %w[MG], '7' => %w[ES RJ], '8' => %w[SP], '9' => %w[PR SC]
  }.freeze

  module_function

  def valido?(cpf)
    return false if cpf.chars.uniq.size == 1

    cpf[9] == digito(cpf[0, 9]) && cpf[10] == digito(cpf[0, 10])
  end

  def digito(base)
    pesos = (2..(base.length + 1)).to_a.reverse
    resto = base.chars.zip(pesos).sum { |caractere, peso| caractere.to_i * peso } * 10 % 11
    (resto == 10 ? 0 : resto).to_s
  end

  def regiao(cpf)
    numero = cpf[8]
    { 'regiao_fiscal' => "#{numero == '0' ? 10 : numero.to_i}ª região fiscal",
      'estados' => REGIOES.fetch(numero).map { |sigla| Autonomia::FerramentasProntas::Ufs.nome(sigla) } }
  end

  CPF = Parametro.new(nome: 'cpf', descricao: 'O CPF como o cliente escreveu (11 dígitos, com ou sem pontos e traço).',
                      pergunte: 'o CPF completo, com os 11 dígitos') do |valor|
    Parametro.digitos(valor, 11)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'cpf', slug: 'pronta_cpf', nome: 'CPF válido', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'Confere se o número de um CPF é válido e em que região fiscal foi emitido. Não traz nome nem situação.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'conferir', descricao: 'se o número é válido e a região', obrigatorios: [CPF], provedores: [Calculo],
        validade: nil, prazo_por_fonte: 1, prazo_total: 1
      )
    ],
    limite_diario: 500,
    termos: 'Calculado na plataforma (regra pública da Receita para os dígitos e a região fiscal). Sem chamada externa ' \
            'e sem cache.'
  )
end
