# O ganho estimado de uma sugestão do painel de desempenho (#2226) em texto, igual à tela: sempre com as datas a que
# se refere, e dito por extenso quando a conta usou o histórico completo porque o período não deu para estimar.
# Quem inclui precisa de `@painel`, `meta` e de Textos.
module Autonomia::Desempenho::Exportacao::Ganho
  # Até 90 dias a duração de um ganho fica em dias ("30 dias"); acima, em meses ("4 meses"), igual à tela.
  MAIOR_DURACAO_EM_DIAS = 90
  DIAS_POR_MES = 30.44

  # O ganho que disputa "por onde começar": o do período; o do histórico completo não compete (-1).
  def ganho_do_periodo(ganho)
    ganho['historico'] ? -1 : (ganho['fechamentos'] || -1)
  end

  # ["≈ 4 vendas", "≈ R$ 1.360"]; sem conta, [].
  def partes_do_ganho(ganho)
    partes = []
    partes << t('acoes.ganho_fechamentos', count: ganho['fechamentos'].to_i, n: numero(ganho['fechamentos'])) if ganho['fechamentos']
    partes << t('acoes.ganho_valor', valor: dinheiro(ganho['valor'], @painel.dig('ticket', 'moeda') || 'BRL')) if ganho['valor']
    partes
  end

  # O ganho sempre diz de que datas é, igual a `fraseDoGanho` da tela: "≈ 4 vendas · ≈ R$ 1.360 em 30 dias (27/09 a
  # 26/10)". Quando o período não deu para estimar e a conta usou o histórico: "neste período ainda não dá para
  # estimar; no histórico completo (4 meses, 25/06 a 26/10): ≈ 19 vendas". Sem conta: nil.
  def frase_do_ganho(ganho, negrito: ->(texto) { texto })
    partes = partes_do_ganho(ganho)
    return nil if partes.empty?

    valores = { ganho: negrito.call(partes.join(' · ')), **periodo_do_ganho(ganho) }
    t(ganho['historico'] ? 'acoes.ganho_do_historico' : 'acoes.ganho_no_periodo', **valores)
  end

  # { duracao: "30 dias" | "4 meses", inicio: "27/09", fim: "26/10" }. Sem o período no ganho, o do painel.
  def periodo_do_ganho(ganho)
    periodo = ganho['periodo'].presence || meta['periodo'].to_h
    dias = periodo['dias'].to_i
    { duracao: duracao_em_texto(dias), inicio: dia_mes(periodo['inicio']), fim: dia_mes(periodo['fim']) }
  end

  def duracao_em_texto(dias)
    return t('formato.duracao_dias', count: dias, n: numero(dias)) if dias <= MAIOR_DURACAO_EM_DIAS

    meses = (dias / DIAS_POR_MES).round
    t('formato.duracao_meses', count: meses, n: numero(meses))
  end
end
