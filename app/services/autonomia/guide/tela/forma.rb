# A forma do que a tela manda ao Guia (#934): o que a pessoa tem aberto,
# selecionado e filtrado.
#
# Só confere a FORMA. Não autoriza nada: quem decide se a pessoa enxerga cada
# id é a leitura prévia (`Tela`), com a permissão dela. Aqui sai o que não pode
# nem chegar lá — recurso fora do catálogo, id que não é inteiro positivo, a
# conta (o Guia já sabe qual é) e o que passa dos tetos.
class Autonomia::Guide::Tela::Forma
  MAX_ABERTOS = 3
  # Acima disso é trabalho para o filtro ou para uma tarefa longa, não para uma lista de ids no prompt.
  MAX_SELECIONADOS = 50
  MAX_FILTROS = 15
  MAX_BYTES_DOS_FILTROS = 1.kilobyte
  MAX_NOME = 80
  CHAVES_DA_CONTA = %w[accountId account_id].freeze

  # `catalogo` é o de leitura da `Consulta`, na linguagem de rota ('crm/cards/:id').
  def initialize(bruto, catalogo:)
    @tela = bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h : {}
    @catalogo = catalogo
  end

  def to_h
    { 'rota' => @tela['rota'].to_s.first(MAX_NOME).presence, 'aberto' => abertos,
      'selecionados' => selecionados, 'filtros' => filtros }.compact_blank
  end

  private

  def abertos
    lista = @tela['aberto']
    return [] unless lista.is_a?(Array)

    lista.filter_map do |item|
      next unless item.is_a?(Hash)

      recurso = recurso(item['recurso'])
      numero = id(item['id'])
      { 'recurso' => recurso, 'id' => numero } if recurso && numero
    end.first(MAX_ABERTOS)
  end

  def selecionados
    bruto = @tela['selecionados']
    return {} unless bruto.is_a?(Hash) && recurso(bruto['recurso'])

    validos = Array(bruto['ids']).filter_map { |valor| id(valor) }.uniq
    return {} if validos.empty?

    total = [id(bruto['total']) || validos.size, validos.size].max
    { 'recurso' => recurso(bruto['recurso']), 'ids' => validos.first(MAX_SELECIONADOS), 'total' => total }
  end

  # Valor simples ou lista de valores simples (`stage_ids: [7]`), até 15 filtros e 1 KB no total.
  def filtros
    bruto = @tela['filtros']
    return {} unless bruto.is_a?(Hash)

    bruto.each_with_object({}) do |(chave, valor), saida|
      next if CHAVES_DA_CONTA.include?(chave.to_s) || !simples?(valor) || saida.size >= MAX_FILTROS

      candidato = saida.merge(chave.to_s.first(MAX_NOME) => valor)
      saida.replace(candidato) if candidato.to_json.bytesize <= MAX_BYTES_DOS_FILTROS
    end
  end

  def simples?(valor)
    return valor.all? { |item| escalar?(item) } if valor.is_a?(Array)

    escalar?(valor)
  end

  def escalar?(valor)
    valor.is_a?(String) || valor.is_a?(Numeric) || valor == true || valor == false
  end

  # O recurso precisa ter leitura por id no catálogo: é por ela que a `Tela` confere cada um.
  def recurso(valor)
    nome = valor.to_s.strip.delete_prefix('/')
    nome if nome.present? && @catalogo.include?("#{nome}/:id")
  end

  def id(valor)
    return nil unless valor.is_a?(Integer) || valor.is_a?(String)

    numero = Integer(valor.to_s, 10, exception: false)
    numero if numero&.positive?
  end
end
