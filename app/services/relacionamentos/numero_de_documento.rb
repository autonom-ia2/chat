# Um CPF ou um CNPJ como número (épico #1240, decisão R1): a forma de comparação, se confere e como aparece.
#
# A forma de comparação é o que o banco guarda e o que a busca compara: só os dígitos do CPF (11), e os 14 caracteres do
# CNPJ em maiúscula. O formato novo do CNPJ, com letra nas 12 primeiras posições, é aceito; os dois últimos seguem dígitos.
#
# Isto compara valor: não lê frase. Quem chama manda só o número. O texto pode ter espaço nas pontas e, no meio, só
# dígito, letra, ponto, barra e hífen; qualquer outro caractere (espaço no meio, dois-pontos, vírgula) faz o texto não
# ser número nenhum. Sem isso, um rótulo na frente do CPF ("CLI 123.456.789-09") ficava com os 14 caracteres de um CNPJ,
# passava na conta do dígito verificador em cerca de 1 caso em 100 e gravava dado de pessoa como CNPJ. Tudo por método
# de texto, sem regex.
#
# Confere quando os dois dígitos verificadores batem (módulo 11). No CNPJ cada caractere vale o código dele menos 48,
# a regra da Receita, que para dígito dá o próprio dígito. Número de um caractere só repetido (000..., 111...) passa na
# conta e não é de ninguém: recusado.
#
# O número inteiro só sai por `canonico` e `formatado`, para quem precisa dele (a ficha, a cotação). `to_s` e `inspect`
# devolvem a forma mascarada, que mostra só os dois dígitos verificadores: é o que vai para lista, log e mensagem de erro.
class Relacionamentos::NumeroDeDocumento
  CPF = 'cpf'.freeze
  CNPJ = 'cnpj'.freeze
  # Conjuntos de caracteres do String#count e do String#delete (não são regex). O hífen vem na frente para valer como hífen.
  DE_DOCUMENTO = '-./0-9A-Z'.freeze
  PONTUACAO = '-./'.freeze
  DIGITOS = '0-9'.freeze
  CODIGO_DO_ZERO = '0'.ord
  # Os pesos de cada dígito verificador: o primeiro sobre o corpo, o segundo sobre o corpo e o primeiro dígito.
  PESOS = {
    CPF => [[10, 9, 8, 7, 6, 5, 4, 3, 2], [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]],
    CNPJ => [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]]
  }.freeze
  TAMANHO_DO_CPF = 11
  TAMANHO_DO_CNPJ = 14
  CORPO_DO_CNPJ = 12

  attr_reader :canonico

  def initialize(texto)
    limpo = texto.to_s.strip.upcase
    @canonico = (limpo.count(DE_DOCUMENTO) == limpo.length ? limpo.delete(PONTUACAO) : '').freeze
  end

  # 'cpf', 'cnpj' ou nil quando o tamanho não é de nenhum dos dois.
  def tipo
    return CPF if canonico.length == TAMANHO_DO_CPF && so_digitos?(canonico)

    CNPJ if canonico.length == TAMANHO_DO_CNPJ && so_digitos?(canonico[CORPO_DO_CNPJ..])
  end

  def cpf?
    tipo == CPF
  end

  def valido?
    return false if tipo.nil? || canonico.chars.uniq.one?

    valores = canonico.each_char.map { |caractere| caractere.ord - CODIGO_DO_ZERO }
    PESOS.fetch(tipo).all? { |pesos| verificador(valores.first(pesos.size), pesos) == valores[pesos.size] }
  end

  # Com a pontuação de costume: 000.000.000-00 e 00.000.000/0000-00. Nil quando o número não confere.
  def formatado
    return unless valido?

    case tipo
    when CPF then "#{canonico[0, 3]}.#{canonico[3, 3]}.#{canonico[6, 3]}-#{canonico[9, 2]}"
    when CNPJ then "#{canonico[0, 2]}.#{canonico[2, 3]}.#{canonico[5, 3]}/#{canonico[8, 4]}-#{canonico[12, 2]}"
    end
  end

  # Só os dois dígitos verificadores à vista: ***.***.***-00 e **.***.***/****-00. Nil quando o número não confere:
  # do que não é documento não se mostra pedaço nenhum.
  def mascarado
    return unless valido?

    case tipo
    when CPF then "***.***.***-#{canonico[9, 2]}"
    when CNPJ then "**.***.***/****-#{canonico[12, 2]}"
    end
  end

  def to_s
    mascarado.to_s
  end

  def inspect
    "#<#{self.class.name} #{mascarado || 'não confere'}>"
  end

  private

  def so_digitos?(texto)
    texto.count(DIGITOS) == texto.length
  end

  def verificador(valores, pesos)
    resto = valores.zip(pesos).sum { |valor, peso| valor * peso } % 11
    resto < 2 ? 0 : 11 - resto
  end
end
