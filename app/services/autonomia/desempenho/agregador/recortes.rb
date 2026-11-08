# Temas, cortes, origem e mapa de horários do painel de desempenho (#2251), como no protótipo.
module Autonomia::Desempenho::Agregador::Recortes
  private

  def temas(lista, anteriores) # rubocop:disable Metrics/AbcSize
    ant = anteriores&.pluck('tema_id')&.tally
    extra = lambda do |id, grupo|
      atuou = grupo.reject { |p| p['qualidade_id'] == 'nao_atuou' }
      { 'acerto_pct' => pct(atuou.count { |p| p['qualidade_id'] == 'acertou' }, atuou.size),
        'erro_grave_pct' => pct(atuou.count { |p| p['qualidade_id'] == 'erro_grave' }, atuou.size),
        'motivo_principal_id' => motivo_principal(grupo), 'anterior_procuras' => ant&.fetch(id, 0) }
    end
    { 'base' => lista.size,
      'ranking' => ranking(lista, lista.size, chave: ->(p) { p['tema_id'] }, nome: ->(id) { cat.dig('temas', id) }, extra: extra),
      'outros' => { 'procuras' => 0 } }
  end

  def motivo_principal(lista)
    Autonomia::Desempenho::Conta.contagem(lista.flat_map { |p| Array(p['motivo_ids']) }).first&.first
  end

  def cortes(lista, compra)
    Array(cfg['cortes']).map do |corte|
      base = corte['base'] == 'todas' ? lista : compra
      nomes = cat.dig('cortes', corte['id']) || {}
      { 'id' => corte['id'], 'nome' => corte['nome'], 'base' => base.size,
        'ranking' => ranking(base, base.size, chave: ->(p) { p.dig('cortes', corte['id']) }, nome: ->(id) { nomes[id] }) }
    end
  end

  def origem(lista)
    grupos = ranking(lista, lista.size, chave: ->(p) { p['origem_id'] }, nome: ->(id) { cat.dig('origens', id, 'nome') })
             .map { |g| g.merge('tipo' => cat.dig('origens', g['id'], 'tipo')) }
    base = { 'anuncios_ligados' => anuncios_ligados?, 'grupos' => grupos, 'nota' => fixos[:origem_nota] }
    return base.merge('comparacao' => nil, 'anuncios' => [], 'sem_saber_qual' => 0) unless anuncios_ligados?

    origem_com_anuncio(lista, base)
  end

  # Conta com anúncio ligado: a mesma conta do protótipo (por anúncio, sem gasto nesta fase).
  def origem_com_anuncio(lista, base) # rubocop:disable Metrics/AbcSize
    an = lista.select { |p| tipo_origem(p) == 'anuncio' }
    resumo = ->(sel) { linha(sel, lista.size).slice('procuras', 'compra', 'fecharam', 'taxa_pct') }
    anuncios = Array(fixos[:anuncios]).filter_map do |anuncio|
      sel = an.select { |p| p['anuncio_id'] == anuncio['id'] }
      next if sel.empty?

      { 'id' => anuncio['id'], 'nome' => anuncio['nome'], 'campanha' => anuncio['campanha'] }
        .merge(resumo.call(sel)).merge('gasto' => nil, 'custo_por_fechou' => nil)
    end
    base.merge('comparacao' => { 'anuncio' => resumo.call(an), 'sem_anuncio' => resumo.call(lista - an) },
               'anuncios' => anuncios.sort_by { |a| [-a['procuras'], a['id'].to_s] },
               'sem_saber_qual' => an.count { |p| p['anuncio_id'].nil? })
  end

  def horarios(lista)
    { 'mapa' => mapa_de(lista), 'mapa_sem_pessoa' => mapa_de(lista.select { |p| p['precisava_pessoa'] && !p['teve_pessoa'] }),
      'total' => lista.size,
      'faixas' => {
        'dentro' => faixa(lista) { |p| dentro_do_horario?(p) },
        'fora' => faixa(lista) { |p| !dentro_do_horario?(p) },
        'fim_de_semana' => faixa(lista) { |p| Autonomia::Desempenho::Conta.data(p['inicio']).cwday >= 6 },
        'noite' => faixa(lista) { |p| Autonomia::Desempenho::Conta.hora(p['inicio']) >= 18 }
      } }
  end

  # 7 linhas (segunda a domingo) × 24 horas.
  def mapa_de(lista)
    mapa = Array.new(7) { Array.new(24, 0) }
    lista.each do |p|
      mapa[Autonomia::Desempenho::Conta.data(p['inicio']).cwday - 1][Autonomia::Desempenho::Conta.hora(p['inicio'])] += 1
    end
    mapa
  end

  def faixa(lista, &)
    sel = lista.select(&)
    linha(sel, lista.size).merge('precisavam_pessoa' => sel.count { |p| p['precisava_pessoa'] },
                                 'tiveram_pessoa' => sel.count { |p| p['precisava_pessoa'] && p['teve_pessoa'] })
  end
end
