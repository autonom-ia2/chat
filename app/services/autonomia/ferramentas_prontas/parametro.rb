# Um parâmetro de uma consulta do catálogo (#2858, F0): o nome que o modelo vê, o tipo no schema, a descrição e como o
# valor é normalizado ANTES de ir à fonte. A normalização é a defesa do endereço: o que vai no caminho é sempre dígito,
# letra maiúscula ou uma opção da lista, e nada do que o modelo escreveu entra cru. Valor que não normaliza é pedido
# inválido (o agente confere com o cliente), e nenhuma fonte é chamada.
#
# `padrao`: o valor quando o modelo não informa (ex.: "de hoje" na contagem de dias úteis), calculado na hora, antes do
# cache: a chave do cache leva o valor efetivo.
# `local: true`: o valor só filtra a resposta aqui dentro e nunca vai à fonte (ex.: a busca por nome de modelo da FIPE).
# `deduza:` / `pergunte:` (regra "QI 70" do Rodrigo, 11/11/2026): o que o agente faz quando o valor falta ou não serve.
# Dado que dá para deduzir da conversa (a UF pela cidade, o DDD pelo telefone): `deduza:` diz como, e o agente corrige
# sem perguntar. Dado que muda o resultado e não dá para deduzir (o CPF, o ano do carro): `pergunte:` diz o quê.
# Sem regex: método de string (`delete`, `count`) e a regra de cada documento.
class Autonomia::FerramentasProntas::Parametro
  DIGITOS = '0-9'.freeze
  ALFANUMERICO = '0-9A-Z'.freeze
  MAX_TEXTO = 60

  attr_reader :nome, :tipo, :descricao, :opcoes

  def initialize(nome:, descricao:, tipo: 'string', opcoes: nil, local: false, padrao: nil, deduza: nil, pergunte: nil, # rubocop:disable Metrics/ParameterLists
                 &normalizar)
    @deduza = deduza
    @pergunte = pergunte
    @padrao = padrao
    @nome = nome
    @tipo = tipo
    @descricao = descricao
    @opcoes = opcoes
    @local = local
    @com_normalizador = !normalizar.nil?
    @normalizar = normalizar || ->(valor) { valor }
  end

  def local?
    @local
  end

  def padrao
    @padrao&.call
  end

  # O texto da recusa deste parâmetro, ou nil (vale o genérico da `Resposta`).
  def orientacao
    return Autonomia::FerramentasProntas::Resposta.deduza(nome, @deduza) if @deduza

    Autonomia::FerramentasProntas::Resposta.pergunte(nome, @pergunte) if @pergunte
  end

  # -> o valor normalizado, ou nil quando não serve (lista e objeto nunca servem: o parâmetro é um valor só). O marcador
  # do valor que já não normalizou (`Fonte::FORA_DO_FORMATO`) nunca serve: sem isto, o parâmetro de texto livre o
  # aceitava, e "(fora do formato)" ia no endereço da fonte (varredura F04 a F07).
  def normalizar(valor)
    return nil if vazio?(valor) || valor == Autonomia::FerramentasProntas::Fonte::FORA_DO_FORMATO
    return opcao(valor) || (@normalizar.call(valor) if @com_normalizador) if opcoes

    @normalizar.call(valor)
  end

  # A forma no schema da ferramenta (`strict: true`): o opcional aceita `null` no tipo.
  def schema(obrigatorio:)
    base = { 'type' => obrigatorio ? tipo : [tipo, 'null'], 'description' => descricao }
    return base unless opcoes

    base.merge('enum' => obrigatorio ? opcoes : opcoes + [nil])
  end

  private

  def vazio?(valor)
    valor.nil? || valor.is_a?(Hash) || valor.is_a?(Array) || (valor.respond_to?(:empty?) && valor.empty?)
  end

  # Com opções, o bloco (se houver) traduz o valor para uma delas: a UF pelo nome do estado. O que ele devolve fora da
  # lista não serve.
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

    # Inteiro dentro da faixa: 2020, "2020" e 2020.0 passam; "2020a" e 2020.5 não.
    def inteiro(valor, faixa)
      valor = valor.to_i if valor.is_a?(Float) && valor.finite? && valor == valor.to_i
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
    # verificadores, conferidos pelo módulo 11 com o valor de cada caractere (código ASCII menos 48). Primeiro só os
    # dígitos, como no CEP e no CPF: o texto em volta ("cnpj 33.000.167/0001-01") sai (varredura F10).
    def cnpj(valor)
      numerico = cnpj_valido(valor.to_s.delete("^#{DIGITOS}"))
      return numerico if numerico

      cnpj_valido(valor.to_s.upcase.delete("^#{ALFANUMERICO}"))
    end

    def cnpj_valido(texto)
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
