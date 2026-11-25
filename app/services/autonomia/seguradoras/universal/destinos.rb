# Os países que a Universal atende, guardados por um dia: a lista muda pouco e a cotação a consulta a cada pedido.
# Guarda só a sigla do país em maiúsculas. Quando a Universal não responde, `siglas` devolve nil e a falha não fica
# guardada. Lista vazia conta como falha: com ela toda sigla seria inválida por um dia inteiro. Quem chama não
# barra a cotação por isso; a própria Universal recusa o destino que não atende.
module Autonomia::Seguradoras::Universal::Destinos
  CHAVE = 'autonomia:universal:destinos:v1'.freeze
  VALIDADE = 1.day

  module_function

  def siglas(cliente)
    lista = Rails.cache.fetch(CHAVE, expires_in: VALIDADE, skip_nil: true) { buscar(cliente) }
    lista&.to_set
  end

  # -> [todas_validas, siglas_que_a_universal_nao_atende]
  def validas?(siglas_pedidas, cliente)
    atendidas = siglas(cliente)
    return [true, []] if atendidas.nil?

    invalidas = Array(siglas_pedidas).map { |sigla| sigla.to_s.upcase }.reject { |sigla| atendidas.include?(sigla) }
    [invalidas.empty?, invalidas]
  end

  def buscar(cliente)
    destinos = cliente.destinos
    return nil unless destinos.is_a?(Array)

    siglas = destinos.filter_map { |destino| destino['siglaPais'].to_s.upcase.presence if destino.is_a?(Hash) }.uniq
    siglas.presence
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro
    nil
  end
  private_class_method :buscar
end
