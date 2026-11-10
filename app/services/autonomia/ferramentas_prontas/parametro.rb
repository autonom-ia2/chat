# Um parâmetro de uma consulta do catálogo (#2858, F0): o nome que o modelo vê, o tipo no schema, a descrição e como o
# valor é normalizado ANTES de ir à fonte. A normalização é a defesa do endereço: o que vai no caminho é sempre dígito,
# letra maiúscula ou uma opção da lista, e nada do que o modelo escreveu entra cru. Valor que não normaliza é pedido
# inválido (o agente confere com o cliente), e nenhuma fonte é chamada.
#
# `local: true`: o valor só filtra a resposta aqui dentro e nunca vai à fonte (ex.: a busca por nome de modelo da FIPE).
# Sem regex: método de string (`delete`, `count`) e a regra de cada documento.
class Autonomia::FerramentasProntas::Parametro
  DIGITOS = '0-9'.freeze
  ALFANUMERICO = '0-9A-Z'.freeze
  MAX_TEXTO = 60

  attr_reader :nome, :tipo, :descricao, :opcoes

  def initialize(nome:, descricao:, tipo: 'string', opcoes: nil, local: false, &normalizar)
    @nome = nome
    @tipo = tipo
    @descricao = descricao
    @opcoes = opcoes
    @local = local
    @normalizar = normalizar || ->(valor) { valor }
  end

  def local?
    @local
  end

  # -> o valor normalizado, ou nil quando não serve.
  def normalizar(valor)
    return nil if valor.nil? || (valor.respond_to?(:empty?) && valor.empty?)
    return opcao(valor) if opcoes

    @normalizar.call(valor)
  end

  # A forma no schema da ferramenta (`strict: true`): o opcional aceita `null` no tipo.
  def schema(obrigatorio:)
    base = { 'type' => obrigatorio ? tipo : [tipo, 'null'], 'description' => descricao }
    return base unless opcoes

    base.merge('enum' => obrigatorio ? opcoes : opcoes + [nil])
  end

  private

  def opcao(valor)
    texto = valor.to_s.strip.downcase
    opcoes.include?(texto) ? texto : nil
  end

  class << self
    # Só os dígitos, com o tamanho exato: "01001-000" -> "01001000".
    def digitos(valor, tamanho)
      texto = valor.to_s.delete("^#{DIGITOS}")
      texto.length == tamanho ? texto : nil
    end

    # Inteiro dentro da faixa: 2020, "2020" e 2020.0 passam; "2020a" não.
    def inteiro(valor, faixa)
      numero = valor.is_a?(Integer) ? valor : Integer(valor.to_s.strip, 10, exception: false)
      numero if numero && faixa.cover?(numero)
    end

    # Código numérico de um item de lista da fonte (marca, modelo): só dígitos, até 10.
    def codigo(valor)
      texto = valor.to_s.strip
      texto if texto.present? && texto.length <= 10 && texto.delete(DIGITOS).empty?
    end

    def texto_curto(valor)
      texto = valor.to_s.squish
      texto.presence&.first(MAX_TEXTO)
    end

    # CNPJ numérico ou alfanumérico (Receita, a partir de 07/2026): 12 posições de letra ou dígito e 2 dígitos
    # verificadores, conferidos pelo módulo 11 com o valor de cada caractere (código ASCII menos 48).
    def cnpj(valor)
      texto = valor.to_s.upcase.delete("^#{ALFANUMERICO}")
      return nil unless texto.length == 14 && texto[12, 2].delete(DIGITOS).empty?
      return nil if texto.chars.uniq.size == 1

      texto if texto[12, 2] == digitos_do_cnpj(texto[0, 12])
    end

    def digitos_do_cnpj(base)
      primeiro = digito_do_cnpj(base)
      "#{primeiro}#{digito_do_cnpj("#{base}#{primeiro}")}"
    end

    def digito_do_cnpj(texto)
      pesos = ([2, 3, 4, 5, 6, 7, 8, 9] * 2).first(texto.length).reverse
      soma = texto.chars.zip(pesos).sum { |caractere, peso| (caractere.ord - 48) * peso }
      resto = soma % 11
      resto < 2 ? 0 : 11 - resto
    end
  end
end
