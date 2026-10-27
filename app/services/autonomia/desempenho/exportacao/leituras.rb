# As frases do painel de desempenho (#2226) que o PDF e a planilha repetem: os 8 números com a explicação de uma
# linha e a comparação com o período anterior, as leituras rápidas (só o que os números não dizem: mensagens, maior
# trava e por onde começar, iguais à tela) e as ressalvas da conferência. Montadas do contrato, sem IA.
# Quem inclui precisa de `@painel` e de Textos.
module Autonomia::Desempenho::Exportacao::Leituras
  include Autonomia::Desempenho::Exportacao::Ganho

  KPIS = %w[procuras conversas compra fecharam duvidas_resolvidas sem_pessoa perdas_evitaveis tempo_resposta].freeze

  def meta
    @painel['meta']
  end

  def nomes
    meta['nomes'].to_h
  end

  def catalogo
    @painel['catalogo'].to_h
  end

  def kpi(id)
    @painel['kpis'].find { |item| item['id'] == id } || {}
  end

  def base_n(id)
    kpi(id)['base'].to_h
  end

  # As ressalvas da conferência de uma parte (campo com nota que afeta a parte), em frase pronta, igual a `ressalvasDe`
  # da tela: ficam perto do número, não só no "Como ler".
  def ressalvas_de(*partes)
    Array(@painel.dig('confianca', 'campos')).filter_map do |campo|
      ressalva_do_campo(campo) if campo['nota'].present? && partes.intersect?(Array(campo['afeta']))
    end
  end

  def ressalva_do_campo(campo)
    leitura = t("como_ler.leitura.#{campo['leitura']}").downcase
    t('como_ler.ressalva_do_campo', campo: campo['nome'], leitura: leitura, pct: pct(campo['acerto_pct']), nota: campo['nota'])
  end

  # A maior trava de quem pediu compra, igual a `maiorTravaDaCompra` da tela: o jeito mais comum de uma procura de
  # compra terminar sem fechar, na base das procuras de compra (sem testes). Os motivos anotados (outra base) ficam
  # só em Perdas. { nome:, n:, m:, pct: } ou nil.
  def maior_trava_da_compra
    compra = Array(@painel['procuras']).select { |procura| procura['compra'] && !procura['teste'] }
    id, n = como_terminaram_sem_fechar(compra).min_by { |chave, quantas| [-quantas, chave] }
    return nil if id.nil?

    { nome: nome_de(catalogo, 'resultados', id), n: n, m: compra.size, pct: parte(n, compra.size) }
  end

  # { id do resultado => quantas } das procuras que não fecharam.
  def como_terminaram_sem_fechar(procuras)
    procuras.map { |procura| procura['resultado_id'].to_s }.reject { |id| grupo_do_resultado(id) == 'fechou' }.tally
  end

  def grupo_do_resultado(id)
    catalogo.dig('resultados', id.to_s, 'grupo')
  end

  # O que mais trava num tema só ganha nome quando é outro que não o mais comum do período (senão repete em toda
  # linha), igual à tela; quando é o mesmo, "a mais comum do período". Sem motivo: nil.
  def trava_do_tema(tema)
    return nil if tema['motivo_principal_id'].blank?

    trava_propria?(tema) ? nome_de(catalogo, 'motivos', tema['motivo_principal_id']) : t('temas.trava_geral')
  end

  def trava_propria?(tema)
    tema['motivo_principal_id'].present? && tema['motivo_principal_id'] != Array(@painel.dig('motivos', 'ranking')).first&.dig('id')
  end

  # "8,6% fecharam (7 de 81)"; com poucos pedidos de compra, a contagem e "poucos casos" (igual à tela); sem, nil.
  def frase_de_fechou(chave, fecharam, compra, taxa)
    return nil if compra.to_i.zero?

    valores = { pct: pct(taxa), n: numero(fecharam), m: numero(compra), fechou: nomes['fechou'].to_s.downcase }
    poucos_casos?(compra) ? t("#{chave}_poucos", **valores) : t(chave, **valores)
  end

  # A sugestão para começar, igual a `sugestaoPrincipal` da tela: entre as que já dá para usar, a de maior ganho NO
  # PERÍODO. Ganho do histórico completo (o período não deu para estimar) não disputa com ganho do período.
  def sugestao_principal
    prontas = Array(@painel['recomendacoes']).select { |item| item['pronto'] == 'ja_da' }
    prontas.max_by { |item| ganho_do_periodo(item['ganho'].to_h) }
  end

  # O primeiro nome do agente para o meio da frase ("Duda mandou…"), igual a `nomeCurtoDoAgente` do painel.
  def nome_do_agente
    meta.dig('agente', 'nome').to_s.strip.split.first.presence || t('agente')
  end

  # A frente de uma sugestão ("Ensinar Duda", "Equipe"); frente desconhecida mostra o id dela.
  def frente_da_recomendacao(frente)
    t("acoes.frente.#{frente}", nome: nome_do_agente, default: frente.to_s)
  end

  # [{ id:, rotulo:, valor:, explicacao:, delta:, sentido:, cor: }] na ordem da tela.
  def numeros_do_painel
    KPIS.map do |id|
      item = kpi(id)
      delta, sentido = delta_do_kpi(item)
      { id: id, rotulo: rotulo_do_kpi(id), valor: valor_do_kpi(item), explicacao: explicacao_do_kpi(item),
        delta: delta, sentido: sentido, cor: item['cor'] || 'neutro' }
    end
  end

  def rotulo_do_kpi(id)
    return nomes['compra'].presence || t('kpi.compra') if id == 'compra'
    return nomes['fechou'].presence || t('kpi.fecharam') if id == 'fecharam'

    t("kpi.#{id}", nome: nome_do_agente)
  end

  def valor_do_kpi(item)
    return pct(parte(item.dig('base', 'n'), item.dig('base', 'm'))) if item['id'] == 'duvidas_resolvidas'
    return segundos(item['valor']) if item['formato'] == 'segundos'

    numero(item['valor'])
  end

  def explicacao_do_kpi(item)
    base = item['base'].to_h
    valores = { n: numero(base['n']), m: numero(base['m']), pct: pct(parte(base['n'], base['m'])),
                explicacao: nomes['compra_explicacao'].to_s, compra: nomes['compra'].to_s.downcase,
                p90: segundos(item.dig('extra', 'p90')), composicao: composicao(item) }
    t("kpi_explicacao.#{item['id']}", **valores)
  end

  def composicao(item)
    Array(item['composicao']).map { |parte| "#{numero(parte['valor'])} #{parte['nome']}" }.join(' + ')
  end

  # ['▲ 14 a mais que no período anterior', :favoravel] ou [nil, nil] sem período anterior. Taxa (dúvidas
  # resolvidas) compara em pontos, com a base de cada período.
  def delta_do_kpi(item)
    return delta_em_pontos(item) if item['id'] == 'duvidas_resolvidas'
    return [nil, nil] if item['anterior'].nil? || item['valor'].nil?

    diferenca = item['valor'] - item['anterior']
    return [t('delta.igual'), :neutro] if diferenca.zero?

    texto = item['formato'] == 'segundos' ? segundos(diferenca.abs) : numero(diferenca.abs)
    chave = diferenca.positive? ? 'delta.mais' : 'delta.menos'
    [t(chave, n: texto), sentido_do_delta(item['melhor'], diferenca)]
  end

  def delta_em_pontos(item)
    agora = parte(item.dig('base', 'n'), item.dig('base', 'm'))
    antes = parte(item.dig('anterior_base', 'n'), item.dig('anterior_base', 'm'))
    return [nil, nil] if agora.nil? || antes.nil?

    diferenca = (agora - antes).round(1)
    return [t('delta.igual'), :neutro] if diferenca.zero?

    chave = diferenca.positive? ? 'delta.pontos_mais' : 'delta.pontos_menos'
    [t(chave, n: decimal(diferenca.abs)), sentido_do_delta(item['melhor'], diferenca)]
  end

  def sentido_do_delta(melhor, diferenca)
    return :neutro if melhor.blank?

    (melhor == 'subir') == diferenca.positive? ? :favoravel : :desfavoravel
  end

  # [{ titulo:, texto: }]. `negrito` embrulha cada número e `escapar` cada nome vindo do dado (no PDF viram <b> e
  # entidades do texto formatado; na planilha ficam como estão).
  def leituras_rapidas(negrito: ->(texto) { texto }, escapar: ->(texto) { texto })
    @escapar = escapar
    [leitura_volume(negrito), leitura_trava(negrito), leitura_decisao(negrito)].compact
  end

  private

  def leitura_volume(negrito)
    mensagens = meta.dig('base', 'mensagens').to_h
    { titulo: t('leituras.volume_titulo'),
      texto: t('leituras.volume', conversas: negrito.call(numero(kpi('conversas')['valor'])), nome: @escapar.call(nome_do_agente),
                                  agente: negrito.call(numero(mensagens['agente'])), equipe: negrito.call(numero(mensagens['equipe']))) }
  end

  def leitura_trava(negrito)
    trava = maior_trava_da_compra
    return { titulo: t('leituras.trava_titulo'), texto: t('leituras.sem_trava') } if trava.nil?

    { titulo: t('leituras.trava_titulo'),
      texto: t('leituras.trava', nome: @escapar.call(trava[:nome].to_s), n: negrito.call(numero(trava[:n])),
                                 base: negrito.call(numero(trava[:m])), compra: @escapar.call(nomes['compra'].to_s.downcase),
                                 pct: negrito.call(pct(trava[:pct]))) }
  end

  def leitura_decisao(negrito)
    sugestao = sugestao_principal
    return nil if sugestao.nil?

    ganho = sugestao['ganho'].to_h
    titulo = @escapar.call(sugestao['titulo'].to_s)
    frase = frase_do_ganho(ganho.except('valor'), negrito: negrito) if ganho['fechamentos'].to_i.positive?
    texto = frase ? t('leituras.decisao_com_ganho', titulo: titulo, ganho: frase) : t('leituras.decisao', titulo: titulo)
    { titulo: t('leituras.decisao_titulo'), texto: texto }
  end
end
