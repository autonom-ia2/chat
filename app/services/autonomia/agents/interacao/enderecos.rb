# Os endereços que o botão de link pode levar (#1479): só os que o DONO autorizou (`do_dono`), inteiros.
#
# Cada palavra do texto (separada por espaço) que contém "http" (sem diferenciar caixa) vira candidata a partir dali,
# sem a pontuação colada no fim (o ponto final da frase, o parêntese do markdown); quem decide se é endereço é o
# Addressable: http ou https, com host. Sem regex. O pedido do modelo vale só se for IGUAL a um deles depois de
# normalizar (esquema e host em minúsculas, o resto igual): pedaço de endereço, ou endereço a mais, nunca vale.
module Autonomia::Agents::Interacao::Enderecos
  ESQUEMAS = %w[http https].freeze
  PONTUACAO_DO_FIM = ['.', ',', ';', ':', '!', '?', ')', ']', '}', '>', '"', "'", '*', '_'].freeze
  # Barra invertida (o navegador a trata como `/`) e barra codificada: com elas o prefixo do caminho do dono não prova nada.
  BARRAS_DISFARCADAS = %w[%5C %2F].freeze

  module_function

  # -> Set dos endereços que o botão pode levar neste turno:
  #   - os que estão em `dono` (a instrução do agente e a base de conhecimento);
  #   - os das saídas de `ferramentas` (HTTP, sistema) que ficam DENTRO de um endereço do dono (`dentro?`): o dono
  #     autoriza o endereço, a ferramenta traz o resto do caminho.
  # Mensagem já gravada na conversa não entra, nem a do próprio agente: `content_attributes` e o remetente de uma
  # mensagem podem ser gravados pela API, e uma nota privada também os leva. Fala do cliente, saída de especialista ou
  # ajudante e memória também não entram.
  def do_dono(dono:, ferramentas:)
    do_dono = dos_textos(dono)
    das_ferramentas = dos_textos(ferramentas).select { |endereco| do_dono.any? { |base| dentro?(endereco, base) } }
    do_dono | das_ferramentas
  end

  # O `endereco` começa pelo endereço do dono (`base`): o mesmo esquema, host e porta (a padrão do esquema quando não
  # vem escrita), e o caminho do dono como prefixo em segmento inteiro (`/a` cobre `/a` e `/a/b`, nunca `/ab`); caminho com
  # barra invertida ou barra codificada (`BARRAS_DISFARCADAS`, depois de normalizar) não vale.
  # Endereço do dono só com host (sem caminho, ou só "/") libera o host inteiro naquele esquema e porta. A consulta
  # (`?`) e o fragmento (`#`) do endereço do dono não restringem.
  def dentro?(endereco, base)
    uri = Addressable::URI.parse(endereco).normalize # sem `..` e `.` no caminho: `/a/../b` é `/b`
    dono = Addressable::URI.parse(base).normalize
    return false unless [uri.scheme, uri.host, uri.inferred_port] == [dono.scheme, dono.host, dono.inferred_port]
    return false if BARRAS_DISFARCADAS.any? { |barra| uri.path.upcase.include?(barra) }

    prefixo = dono.path.delete_suffix('/')
    prefixo.empty? || uri.path == prefixo || uri.path.start_with?("#{prefixo}/")
  end

  # -> Set dos endereços normalizados que aparecem nos textos.
  def dos_textos(textos)
    textos.compact.flat_map { |texto| texto.to_s.split }.filter_map { |palavra| candidato(palavra) }.to_set
  end

  # -> o endereço normalizado, ou nil quando não é http(s) com host, ou quando traz usuário e senha (`user@`), em
  # qualquer fonte e no pedido do modelo.
  def normalizado(endereco)
    return unless endereco.is_a?(String)

    uri = Addressable::URI.parse(endereco)
    return unless ESQUEMAS.include?(uri.scheme.to_s.downcase) && uri.host.present? && uri.userinfo.nil?

    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def candidato(palavra)
    inicio = palavra.downcase(:ascii).index('http') # só ASCII: as posições não mudam
    return if inicio.nil?

    endereco = palavra[inicio..]
    endereco = endereco[0...-1] while PONTUACAO_DO_FIM.any? { |sinal| endereco.end_with?(sinal) }
    normalizado(endereco)
  end
end
