# Confere a ficha antes da primeira chamada paga da rodada (#2301): ficha com catálogo ou faixas quebrados faria cada
# conversa ser cobrada e recusada depois. Devolve a lista de problemas (vazia quando dá para ler); os textos citam só
# o nome da parte, nunca conteúdo.
class Autonomia::Desempenho::LeituraAutomatica::ConferenciaDaFicha
  def initialize(ficha)
    @ficha = ficha
  end

  def problemas
    return ['catalogo'] unless @ficha.catalogo.is_a?(Hash)

    quebrados = (listas + cortes + extras).uniq
    quebrados.presence || listas_vazias
  end

  private

  def configuracao = @ficha.configuracao

  # As listas do catálogo que viram campo são objetos {id => nome}; os cortes, {id do corte => {id => nome}}.
  def listas
    quebradas = Autonomia::Desempenho::LeituraAutomatica::Esquema::LISTAS.values.uniq.reject { |nome| @ficha.catalogo[nome].is_a?(Hash) }
    do_corte = @ficha.catalogo['cortes']
    quebradas << 'cortes' unless do_corte.nil? || (do_corte.is_a?(Hash) && do_corte.values.all?(Hash))
    quebradas
  end

  # Cada corte tem id e campo; as faixas são [de, até | nil, nome], com de <= até.
  def cortes
    Array(configuracao['cortes']).flat_map do |corte|
      next ['cortes'] unless corte_com_nome?(corte)

      faixas_validas?(corte['faixas']) ? [] : ["faixas de #{corte['id']}"]
    end
  end

  def corte_com_nome?(corte) = corte.is_a?(Hash) && corte['id'].is_a?(String) && corte['campo'].is_a?(String)

  # Sem faixas é corte de lista (vale o catálogo); com faixas, todas precisam estar certas.
  def faixas_validas?(faixas)
    faixas.nil? || (faixas.is_a?(Array) && faixas.all? { |faixa| faixa.is_a?(Array) && faixa.size == 3 && faixa_valida?(*faixa) })
  end

  def faixa_valida?(minimo, maximo, nome)
    minimo.is_a?(Integer) && nome.is_a?(String) && (maximo.nil? || (maximo.is_a?(Integer) && maximo >= minimo))
  end

  def extras
    leitura = configuracao['leitura']
    lista = leitura.is_a?(Hash) ? leitura['extras'] : nil
    return [] if lista.nil?

    lista.is_a?(Hash) && lista.values.all?(Hash) ? [] : ['leitura.extras']
  end

  # O esquema estrito recusa lista fechada vazia: o catálogo precisa ter cada lista que vira campo.
  def listas_vazias
    propriedades = Autonomia::Desempenho::LeituraAutomatica::Esquema.new(@ficha).json.dig('properties', 'procuras', 'items', 'properties')
    propriedades.filter_map do |nome, definicao|
      lista = definicao['enum'] || definicao.dig('items', 'enum')
      nome if lista && lista.empty?
    end
  end
end
