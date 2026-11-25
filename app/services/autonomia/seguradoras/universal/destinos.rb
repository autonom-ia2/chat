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
    validas_em?(siglas_pedidas, paises(cliente))
  end

  # -> o nome de cada sigla, na ordem pedida. Sigla que a Universal não nomeia (ou a Universal fora) fica a sigla.
  def nomes(siglas_pedidas, cliente)
    nomes_em(siglas_pedidas, paises(cliente))
  end

  # -> { 'PT' => 'Portugal', ... }, ou nil quando a Universal não respondeu. Quem confere e nomeia no mesmo pedido lê
  # uma vez e passa o mapa a `validas_em?` e `nomes_em`: com a Universal fora nada fica no cache, e ler duas vezes
  # seriam duas chamadas.
  def paises(cliente)
    Rails.cache.fetch(CHAVE, expires_in: VALIDADE, skip_nil: true) { buscar(cliente) }
  end

  # `validas?` sobre um mapa já lido. Mapa nil (Universal fora) não barra.
  def validas_em?(siglas_pedidas, mapa)
    return [true, []] if mapa.nil?

    invalidas = Array(siglas_pedidas).map { |sigla| sigla.to_s.upcase }.reject { |sigla| mapa.key?(sigla) }
    [invalidas.empty?, invalidas]
  end

  # `nomes` sobre um mapa já lido.
  def nomes_em(siglas_pedidas, mapa)
    Array(siglas_pedidas).map do |sigla|
      sigla = sigla.to_s.upcase
      mapa.to_h[sigla].presence || sigla
    end
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
  private_class_method :buscar
end
