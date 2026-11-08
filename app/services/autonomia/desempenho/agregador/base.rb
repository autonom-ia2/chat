# Classificação de uma procura e as linhas de ranking do painel de desempenho (#2251), como no protótipo.
module Autonomia::Desempenho::Agregador::Base
  private

  def pct(parte, total) = Autonomia::Desempenho::Conta.pct(parte, total)
  def dia_de(data_hora) = Autonomia::Desempenho::Conta.dia_de(data_hora)

  def grupo(item)
    cat.dig('resultados', item['resultado_id'], 'grupo')
  end

  def eh_compra?(item) = @compra_ids.include?(item['pedido_id'])
  def fechou?(item) = grupo(item) == 'fechou'

  # Segunda = 1 ... domingo = 7, como os `dias_semana` do horário comercial.
  def dentro_do_horario?(item)
    @dias_uteis.include?(Autonomia::Desempenho::Conta.data(item['inicio']).cwday) &&
      Autonomia::Desempenho::Conta.hora(item['inicio']).between?(@hora_ini, @hora_fim - 1)
  end

  def tipo_origem(item)
    cat.dig('origens', item['origem_id'], 'tipo') || 'sem_anuncio'
  end

  def anuncios_ligados? = fixos[:anuncios_ligados] == true

  # As procuras de verdade (sem teste) cujo dia de início cai no período, inclusive.
  def reais(inicio, fim)
    ini = inicio.iso8601
    fi = fim.iso8601
    todas.select { |p| !p['teste'] && dia_de(p['inicio']).between?(ini, fi) }
  end

  def linha(lista, base)
    compra = lista.select { |p| eh_compra?(p) }
    fecharam = compra.count { |p| fechou?(p) }
    { 'procuras' => lista.size, 'pct' => pct(lista.size, base), 'compra' => compra.size, 'fecharam' => fecharam,
      'taxa_pct' => pct(fecharam, compra.size) }
  end

  # Agrupa pela `chave`, uma linha por grupo, da maior para a menor (desempate pelo id).
  def ranking(lista, base, chave:, nome:, extra: nil)
    linhas = lista.group_by(&chave).map do |id, grupo|
      item = { 'id' => id, 'nome' => nome.call(id) }.merge(linha(grupo, base))
      extra ? item.merge(extra.call(id, grupo)) : item
    end
    linhas.sort_by { |item| [-item['procuras'], Autonomia::Desempenho::Conta.texto(item['id'])] }
  end

  def numeros(lista) # rubocop:disable Metrics/CyclomaticComplexity
    compra = lista.select { |p| eh_compra?(p) }
    duvidas = lista.select { |p| @duvida_ids.include?(p['pedido_id']) }
    precisavam = lista.select { |p| p['precisava_pessoa'] }
    {
      'procuras' => lista, 'compra' => compra, 'fech' => compra.select { |p| fechou?(p) }, 'duvidas' => duvidas,
      'resolvidas' => duvidas.select { |p| Array(cfg['duvida_resolvida']).include?(p['resultado_id']) },
      'precisavam' => precisavam, 'tiveram' => precisavam.select { |p| p['teve_pessoa'] },
      'perdas' => lista.select { |p| p['perda_evitavel'] }, 'conversas' => lista.pluck('conversa').uniq.sort
    }
  end

  def prova(item)
    { 'conversa' => item['conversa'], 'procura' => item['procura'], 'quando' => item['inicio'], 'resumo' => item['resumo'] }
  end

  def em_ordem(lista)
    lista.sort_by { |p| [p['inicio'], p['conversa'].to_i, p['procura']] }
  end

  def primeiras(lista, quantas = 2)
    em_ordem(lista).first(quantas).map { |p| prova(p) }
  end
end
