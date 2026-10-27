# Funil, taxas entre etapas e comparações A × B do painel de desempenho (#2251), como no protótipo.
module Autonomia::Desempenho::Agregador::Funil
  class ComparacaoInvalida < StandardError; end

  private

  def etapas_cfg = Array(cfg['funil'])

  # Chegou à etapa i: tem um marco dela (Conta.marcos_da_etapa) ou de uma etapa depois. A 1ª etapa é o próprio pedido (toda procura de compra
  # chegou a ela; assim o 1º cartão é a base, 100%).
  def chegou?(item, indice)
    return true if indice.zero?

    marcos = Array(item['marcos'])
    etapas_cfg.drop(indice).any? { |etapa| Autonomia::Desempenho::Conta.marcos_da_etapa(etapa).intersect?(marcos) }
  end

  def indice_da_etapa(etapa_id)
    etapas_cfg.index { |etapa| etapa['id'] == etapa_id }
  end

  def funil(compra)
    anterior = nil
    etapas = etapas_cfg.each_with_index.map do |etapa, i|
      n = compra.count { |p| chegou?(p, i) }
      linha = { 'id' => etapa['id'], 'nome' => etapa['nome'], 'marcos' => etapa['marcos'], 'procuras' => n,
                'pct_do_inicio' => pct(n, compra.size), 'taxa_da_anterior' => anterior.nil? ? nil : pct(n, anterior) }
      anterior = n
      linha
    end
    { 'base' => compra.size, 'etapas' => etapas, 'nota' => cfg['funil_nota'], 'conciliacao' => conciliacao(compra) }
  end

  # Por que a última etapa do funil e "Fecharam" não dão o mesmo número.
  def conciliacao(compra)
    ultima = etapas_cfg.size - 1
    chegaram = compra.select { |p| chegou?(p, ultima) }
    { 'chegaram_ao_fim' => chegaram.size, 'chegaram_e_nao_fecharam' => chegaram.count { |p| !fechou?(p) },
      'fecharam_sem_chegar' => compra.count { |p| fechou?(p) && !chegou?(p, ultima) },
      'fecharam' => compra.count { |p| fechou?(p) } }
  end

  # Só as taxas que não estão nos números do topo: a passagem entre etapas e a passagem para uma pessoa.
  def indicadores(nums, funil) # rubocop:disable Metrics/AbcSize
    e = funil['etapas']
    pares = e.size > 3 ? [[0, 1], [1, 2], [2, e.size - 1]] : (0...(e.size - 1)).map { |i| [i, i + 1] }
    pares.map do |a, b|
      { 'id' => "chegou_#{e[b]['id']}", 'tipo' => 'etapa', 'de_id' => e[a]['id'], 'para_id' => e[b]['id'],
        'n' => e[b]['procuras'], 'm' => e[a]['procuras'], 'pct' => pct(e[b]['procuras'], e[a]['procuras']) }
    end + [{ 'id' => 'pessoa', 'tipo' => 'pessoa', 'de_id' => nil, 'para_id' => nil, 'n' => nums['tiveram'].size,
             'm' => nums['precisavam'].size, 'pct' => pct(nums['tiveram'].size, nums['precisavam'].size) }]
  end

  # Os dois lados usam a mesma base (as de compra que chegaram à `base_etapa`) e só se separam pelo que aconteceu antes
  # do fim; o resultado nunca entra no filtro.
  def base_da_comparacao(regra, compra)
    return compra if regra['base_etapa'].blank?

    i = indice_da_etapa(regra['base_etapa'])
    compra.select { |p| chegou?(p, i) }
  end

  def lado_da_comparacao(lado, lista)
    raise ComparacaoInvalida, "comparação #{lado['id']}: o lado não pode filtrar pelo resultado" if lado['resultados'].present?

    sel = lista.select { |p| no_lado?(lado, p) }
    fecharam = sel.count { |p| fechou?(p) }
    { 'id' => lado['id'], 'nome' => lado['nome'], 'n' => fecharam, 'm' => sel.size, 'pct' => pct(fecharam, sel.size) }
  end

  def no_lado?(lado, item)
    marcos = Array(item['marcos'])
    (lado['marcos'].blank? || Array(lado['marcos']).intersect?(marcos)) &&
      (lado['sem_marcos'].blank? || !Array(lado['sem_marcos']).intersect?(marcos)) &&
      (lado['origens'].blank? || Array(lado['origens']).include?(item['origem_id']))
  end

  def comparacao(regra, compra)
    base = base_da_comparacao(regra, compra)
    { 'id' => regra['id'], 'recorte' => regra['recorte'], 'a' => lado_da_comparacao(regra['a'], base),
      'b' => lado_da_comparacao(regra['b'], base), 'ressalva' => regra['ressalva'] }
  end

  def comparacoes(compra)
    out = Array(cfg['comparacoes']).map { |regra| comparacao(regra, compra) }
    nomes = cfg['nomes_horario'] || {}
    horario = { 'id' => 'horario', 'recorte' => 'horario',
                'a' => lado_do_horario('fora', nomes['fora'], compra.reject { |p| dentro_do_horario?(p) }),
                'b' => lado_do_horario('dentro', nomes['dentro'], compra.select { |p| dentro_do_horario?(p) }), 'ressalva' => nil }
    out.insert([1, out.size].min, horario)
  end

  def lado_do_horario(id, nome, lista)
    fecharam = lista.count { |p| fechou?(p) }
    { 'id' => id, 'nome' => nome, 'n' => fecharam, 'm' => lista.size, 'pct' => pct(fecharam, lista.size) }
  end
end
