# Os países que a Universal atende, guardados por um dia: a lista muda pouco e a cotação a consulta a cada pedido.
# Guarda a sigla do país em maiúsculas e o nome do país como a Universal o escreve (o PDF e a conversa falam
# "Portugal", não "PT"). Quando a Universal não responde, `siglas` devolve nil e a falha não fica guardada. Lista vazia
# conta como falha: com ela toda sigla seria inválida por um dia inteiro. Quem chama não barra a cotação por isso; a
# própria Universal recusa o destino que não atende.
module Autonomia::Seguradoras::Universal::Destinos
  CHAVE = 'autonomia:universal:destinos:v2'.freeze
  VALIDADE = 1.day

  module_function

  def siglas(cliente)
    paises(cliente)&.keys&.to_set
  end

  # -> [todas_validas, siglas_que_a_universal_nao_atende]
  def validas?(siglas_pedidas, cliente)
    atendidas = siglas(cliente)
    return [true, []] if atendidas.nil?

    invalidas = Array(siglas_pedidas).map { |sigla| sigla.to_s.upcase }.reject { |sigla| atendidas.include?(sigla) }
    [invalidas.empty?, invalidas]
  end

  # -> o nome de cada sigla, na ordem pedida. Sigla que a Universal não nomeia (ou a Universal fora) fica a sigla.
  def nomes(siglas_pedidas, cliente)
    mapa = paises(cliente).to_h
    Array(siglas_pedidas).map do |sigla|
      sigla = sigla.to_s.upcase
      mapa[sigla].presence || sigla
    end
  end

  # -> { 'PT' => 'Portugal', ... }, ou nil quando a Universal não respondeu.
  def paises(cliente)
    Rails.cache.fetch(CHAVE, expires_in: VALIDADE, skip_nil: true) { buscar(cliente) }
  end

  def buscar(cliente)
    destinos = cliente.destinos
    return nil unless destinos.is_a?(Array)

    mapa = destinos.each_with_object({}) do |destino, por_sigla|
      next unless destino.is_a?(Hash)

      sigla = destino['siglaPais'].to_s.upcase
      por_sigla[sigla] ||= destino['pais'].to_s.strip if sigla.present?
    end
    mapa.presence
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro
    nil
  end
  private_class_method :paises, :buscar
end
