# Quem procura, conversas mais ativas, vendas perdidas e motivos de trava do painel de desempenho (#2251), como no
# protótipo.
module Autonomia::Desempenho::Agregador::Conversas
  TOP_ATIVAS = 20
  TOP_CONCENTRACAO = 10

  private

  def quem(nums) # rubocop:disable Metrics/AbcSize
    ps = nums['procuras']
    por_conversa = ps.group_by { |p| p['conversa'] }
    top = conversas_ativas(ps).select { |c| c['compra'].positive? }.first(TOP_CONCENTRACAO).pluck('conversa')
    compra_do_top = top.sum { |c| por_conversa[c].count { |p| eh_compra?(p) } }
    { 'base' => ps.size,
      'ranking' => ranking(ps, ps.size, chave: ->(p) { p['quem_id'] }, nome: ->(id) { cat.dig('quem', id) }),
      'concentracao' => {
        'conversas_com_compra' => nums['compra'].pluck('conversa').uniq.size,
        'conversas_com_fechamento' => nums['fech'].pluck('conversa').uniq.size,
        'conversas_uma_procura' => por_conversa.count { |_c, v| v.size == 1 },
        'top10_pct_da_compra' => pct(compra_do_top, nums['compra'].size)
      } }
  end

  # As que mais pediram compra primeiro (a lista e o "% das 10 mais ativas" usam a mesma ordem).
  def conversas_ativas(lista) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ativas = lista.group_by { |p| p['conversa'] }
                  .sort_by { |c, v| [-v.count { |p| eh_compra?(p) }, -v.size, c] }.first(TOP_ATIVAS)
    ativas.map do |c, v|
      tema = Autonomia::Desempenho::Conta.contagem(v.map { |p| p['tema_id'] }).first.first
      { 'conversa' => c, 'procuras' => v.size, 'compra' => v.count { |p| eh_compra?(p) },
        'fecharam' => v.count { |p| eh_compra?(p) && fechou?(p) }, 'primeira' => v.first['inicio'], 'ultima' => v.last['inicio'],
        'tema_id' => tema }
    end
  end

  def perdas(nums) # rubocop:disable Metrics/AbcSize
    perdas = nums['perdas']
    usados = Set.new # uma perda pode ter vários motivos: cada motivo mostra conversas diferentes quando dá
    por_motivo = Autonomia::Desempenho::Conta.contagem(perdas.flat_map { |p| Array(p['motivo_ids']) }).map do |id, v|
      sel = perdas.select { |p| Array(p['motivo_ids']).include?(id) }
      { 'id' => id, 'nome' => cat.dig('motivos', id), 'procuras' => v, 'exemplos' => exemplos_de('perdas', id, sel, 2, usados) }
    end
    por_resultado = Autonomia::Desempenho::Conta.contagem(perdas.map { |p| p['resultado_id'] })
                                                .map { |id, v| { 'id' => id, 'nome' => cat.dig('resultados', id, 'nome'), 'n' => v } }
    { 'total' => perdas.size, 'pct_da_compra' => pct(perdas.size, nums['compra'].size), 'por_motivo' => por_motivo,
      'por_resultado' => por_resultado,
      'lista' => perdas.map do |p|
        prova(p).merge('por_que' => fixos[:por_que][[p['conversa'], p['procura']]], 'resultado_id' => p['resultado_id'],
                       'motivo_ids' => p['motivo_ids'])
      end }
  end

  def motivos(lista)
    com = lista.select { |p| Array(p['motivo_ids']).any? }
    ranking = (cat['motivos'] || {}).filter_map do |id, nome|
      sel = com.select { |p| p['motivo_ids'].include?(id) }
      next if sel.empty?

      { 'id' => id, 'nome' => nome, 'procuras' => sel.size, 'pct' => pct(sel.size, com.size),
        'exemplos' => exemplos_de('motivos', id, sel) }
    end
    { 'base' => lista.size, 'com_motivo' => com.size, 'ranking' => ranking.sort_by { |x| [-x['procuras'], x['id']] } }
  end
end
