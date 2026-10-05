# Os registros que a receita vai mudar (#936), lidos como a pessoa os leria na tela: pela `Consulta`,
# com a permissão dela, página a página. O filtro da receita é por campo e valor, sem texto livre.
#
# A paginação é por forma, não por recurso: pede a página seguinte até uma página não trazer id novo
# (a rota sem paginação devolve a mesma lista de novo, e aí para).
class Autonomia::Guide::Tarefas::Alvos
  Recusada = ::Autonomia::Guide::Tarefas::Recusada
  Montador = ::Autonomia::Guide::Tarefas::Montador
  PARAMETRO = ':id'.freeze

  def initialize(consulta:, receita:)
    @consulta = consulta
    @receita = receita
  end

  # A leitura de UM registro, para o lote e a amostra lerem o dado de agora.
  def rota_do_item
    "#{@receita.recurso}/#{PARAMETRO}"
  end

  def item_legivel?
    @consulta.catalogo.include?(@receita.recurso) && @consulta.catalogo.include?(rota_do_item)
  end

  # -> [registro], no máximo `MAX_ITENS + 1` (o que passa disso já basta para recusar).
  def listar
    raise Recusada, "não sei ler #{@receita.recurso} um por um; use um recurso do catálogo de ler_da_conta" unless item_legivel?

    vistos = {}
    1.upto(::Autonomia::Guide::Tarefa::MAX_ITENS + 1) do |pagina|
      lista, total = pagina_de(pagina)
      demais!(total)
      novos = novos(lista, vistos)
      break if novos.empty?

      novos.each { |item| vistos[item['id']] = item if passa?(item) }
      break if vistos.size > ::Autonomia::Guide::Tarefa::MAX_ITENS
    end
    vistos.values
  end

  # -> o registro, ou nil quando ele sumiu ou a pessoa deixou de ver.
  def ler(id)
    registro(@consulta.json(rota_do_item, @receita.parametros.merge('id' => id.to_s)))
  rescue Recusada, ::Autonomia::Guide::Consulta::Recusada
    nil
  end

  private

  def novos(lista, vistos)
    Array(lista).select { |item| item.is_a?(Hash) && item['id'].present? && !vistos.key?(item['id']) }
  end

  def pagina_de(pagina)
    ::Autonomia::Guide::Resumo.lista_e_total(@consulta.json(@receita.recurso, @receita.parametros, 'page' => pagina))
  rescue ::Autonomia::Guide::Consulta::Recusada => e
    raise Recusada, e.message
  end

  # O total da plataforma, sem filtro, já passa do teto: nem lê o resto.
  def demais!(total)
    return unless @receita.filtro.empty? && total.to_i > ::Autonomia::Guide::Tarefa::MAX_ITENS

    raise Recusada, "são #{total} registros, e uma tarefa vai até #{::Autonomia::Guide::Tarefa::MAX_ITENS}; filtre ou divida"
  end

  def registro(dados)
    return dados if dados.is_a?(Hash) && dados.key?('id')
    return unless dados.is_a?(Hash)

    interno = dados['payload'] || dados['data']
    interno.is_a?(Hash) ? registro(interno) : nil
  end

  def passa?(item)
    @receita.filtro.all? { |condicao| condicao_vale?(Montador.campo(item, condicao['campo']), condicao['op'], condicao['valor']) }
  end

  def condicao_vale?(valor, operador, esperado)
    case operador
    when 'igual' then valor.to_s == esperado.to_s
    when 'diferente' then valor.to_s != esperado.to_s
    when 'vazio' then valor.blank?
    when 'preenchido' then valor.present?
    else comparar(valor, operador, esperado)
    end
  end

  def comparar(valor, operador, esperado)
    atual = numero(valor)
    limite = numero(esperado)
    return false if atual.nil? || limite.nil?

    operador == 'menor' ? atual < limite : atual > limite
  end

  # Número, data ISO ou carimbo em segundos: tudo vira número para comparar.
  def numero(valor)
    return valor.to_f if valor.is_a?(Numeric)
    return if valor.blank?

    Float(valor.to_s, exception: false) || Time.zone.parse(valor.to_s)&.to_f
  rescue ArgumentError
    nil
  end
end
