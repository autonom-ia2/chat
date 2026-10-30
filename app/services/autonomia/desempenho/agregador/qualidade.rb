# Qualidade do agente e passagem para uma pessoa no painel de desempenho (#2251), como no protótipo.
module Autonomia::Desempenho::Agregador::Qualidade
  QUALIDADES = %w[acertou erro_leve erro_grave nao_atuou].freeze
  # Uma regra só "acontece em quase toda conversa" quando passa disto (% das procuras em que o agente atuou).
  QUASE_SEMPRE_PCT = 50
  TOP_TEMAS = 3

  private

  # Exemplos que a leitura escolheu e que caem no período; quando faltar, as primeiras procuras. Com `usados` (as
  # conversas já mostradas em outro item da mesma lista), prefere as que ainda não apareceram.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def exemplos_de(grupo, id, sel, quantos = 2, usados = nil)
    usados ||= Set.new
    no_periodo = sel.index_by { |p| [p['conversa'], p['procura']] }
    escolhidos = Array(fixos.dig(:exemplos, grupo, id)).filter_map { |chave| no_periodo[chave] }
    ordem = escolhidos + em_ordem(sel)
    out = []
    vistos = Set.new
    [true, false].each do |so_novas|
      ordem.each do |p|
        break if out.size >= quantos

        chave = [p['conversa'], p['procura']]
        next if vistos.include?(chave) || (so_novas && usados.include?(p['conversa']))

        vistos << chave
        out << prova(p)
      end
    end
    usados.merge(out.pluck('conversa'))
    out
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Todas as taxas de qualidade têm a mesma base: as procuras em que o agente atuou.
  def qualidade(lista, tempo, mensagens) # rubocop:disable Metrics/AbcSize
    atuou = lista.reject { |p| p['qualidade_id'] == 'nao_atuou' }
    por_tema = qualidade_por_tema(lista, atuou)
    fortes = por_tema.sort_by.with_index { |x, i| [-x['acerto_pct'], -x['procuras'], i] }.first(TOP_TEMAS)
                     .map { |x| x.except('exemplos_de_erro') }
    piores = por_tema.sort_by.with_index { |x, i| [-x['erro_grave_pct'], -x['procuras'], i] }.first(TOP_TEMAS)
                     .map { |x| x.except('exemplos', 'exemplos_de_erro').merge('exemplos' => x['exemplos_de_erro']) }
    { 'base' => atuou.size, 'lidas' => lista.size, 'distribuicao' => QUALIDADES.map { |q| parte_da_qualidade(lista, atuou, q) },
      'regras' => regras_quebradas(atuou), 'pontos_fortes' => fortes, 'piores_temas' => piores,
      'tempo_resposta' => tempo, 'mensagens' => mensagens }
  end

  def parte_da_qualidade(lista, atuou, qualidade)
    c = lista.count { |p| p['qualidade_id'] == qualidade }
    # "Não atuou" fica fora da base: aparece só a contagem.
    { 'id' => qualidade, 'procuras' => c, 'pct' => qualidade == 'nao_atuou' ? nil : pct(c, atuou.size) }
  end

  def regras_quebradas(atuou) # rubocop:disable Metrics/CyclomaticComplexity
    sistemicas = Array(cfg['regras_sistemicas'])
    quebradas = (cat['regras'] || {}).filter_map do |id, regra|
      sel = atuou.select { |p| Array(p['regra_ids']).include?(id) }
      next if sel.empty?

      taxa = pct(sel.size, atuou.size)
      { 'id' => id, 'nome' => regra['nome'], 'descricao' => regra['descricao'], 'procuras' => sel.size, 'pct' => taxa,
        'sistemica' => sistemicas.include?(id) && (taxa || 0) >= QUASE_SEMPRE_PCT, 'exemplos' => exemplos_de('regras', id, sel) }
    end
    quebradas.sort_by { |x| [-x['procuras'], x['id']] }
  end

  # Só temas com volume: pelo menos 5 procuras ou 0,75% das lidas (arredondado como o protótipo, metade para o par).
  def qualidade_por_tema(lista, atuou) # rubocop:disable Metrics/AbcSize
    limiar = [5, (lista.size * 0.0075).round(half: :even)].max
    (cat['temas'] || {}).filter_map do |id, nome|
      sel = atuou.select { |p| p['tema_id'] == id }
      next if sel.size < limiar

      acertos = sel.select { |p| p['qualidade_id'] == 'acertou' }
      graves = sel.select { |p| p['qualidade_id'] == 'erro_grave' }
      { 'tema_id' => id, 'nome' => nome, 'procuras' => sel.size, 'acerto_pct' => pct(acertos.size, sel.size),
        'erro_grave_pct' => pct(graves.size, sel.size), 'exemplos' => exemplos_de('fortes', id, acertos, 1),
        'exemplos_de_erro' => primeiras(graves, 1) }
    end
  end

  def prometida(lista)
    marcos = cfg['marcos_da_passagem']
    return [fixos[:prometida], fixos[:prometida_sem_resposta]] if marcos.blank?

    prometidas = lista.select { |p| Array(p['marcos']).include?(marcos['prometida']) }
    [prometidas.size, prometidas.count { |p| Array(p['marcos']).exclude?(marcos['respondeu']) }]
  end

  def pessoa(nums) # rubocop:disable Metrics/AbcSize
    sem = nums['precisavam'].reject { |p| p['teve_pessoa'] }
    prometida, prometida_sem = prometida(nums['procuras'])
    contar = lambda do |chave, nome|
      Autonomia::Desempenho::Conta.contagem(sem.map(&chave)).map { |id, v| { 'id' => id, 'nome' => nome.call(id), 'n' => v } }
    end
    { 'precisavam' => nums['precisavam'].size, 'tiveram' => nums['tiveram'].size, 'sem_pessoa' => sem.size,
      'sem_pessoa_pct' => pct(sem.size, nums['precisavam'].size),
      'sem_pessoa_fora_do_horario' => sem.count { |p| !dentro_do_horario?(p) },
      'prometida' => prometida, 'prometida_sem_resposta' => prometida_sem, 'equipe_por_mes' => fixos[:equipe_por_mes],
      'por_pedido' => contar.call(->(p) { p['pedido_id'] }, ->(id) { cat.dig('cortes', 'pedido', id) }),
      'por_resultado' => contar.call(->(p) { p['resultado_id'] }, ->(id) { cat.dig('resultados', id, 'nome') }),
      'exemplos' => exemplos_de('sem_pessoa', 'todos', sem, 3) }
  end
end
