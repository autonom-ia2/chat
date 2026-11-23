# Como o relatório do Guia escreve período, tempo e nome (#3158). Portado do `Captain::Copilot::ReportLabels`.
#
# Para o MODELO, datas em AAAA-MM-DD e tempo em segundos com o texto ao lado ("2 dias e 1 hora"): ele escreve
# na língua da pessoa. Para o GRÁFICO, título e rótulos já no idioma do pedido (o `ChatJob` roda no idioma de
# quem perguntou), porque o desenho não passa pelo modelo.
module Autonomia::Guide::Relatorio::Rotulos
  CHAVE = 'autonomia.guide.relatorio'.freeze
  # As duas maiores unidades, como a tela Relatórios escreve.
  UNIDADES = %i[years months weeks days hours minutes seconds].freeze

  module_function

  # O período de um ponto da série. Um dia é a data; semana e mês são o primeiro e o último dia dentro de `de` e
  # `ate`, e `parcial` quando o período escolhido os cortou.
  def periodo(comeco, grupo, pedido)
    return { periodo: comeco.to_date.iso8601 } if grupo == 'day'

    termino = comeco + 1.public_send(grupo)
    primeiro = [comeco, pedido.inicio].max.to_date
    ultimo = ([termino, pedido.fim].min - 1.second).to_date
    rotulo = { periodo: "#{primeiro.iso8601} a #{ultimo.iso8601}" }
    primeiro > comeco.to_date || ultimo < (termino - 1.second).to_date ? rotulo.merge(parcial: true) : rotulo
  end

  # "2 dias e 1 hora". Zero é tempo medido (resposta fora do expediente): "0 segundos". nil é nada medido.
  # O `Duration.build(0).parts` pode vir vazio (depende da versão do Rails), e zero nunca pode virar texto vazio.
  def tempo(segundos)
    return nil if segundos.nil?

    partes = ActiveSupport::Duration.build(segundos.to_f.round).parts.sort_by { |unidade, _| UNIDADES.index(unidade) }
    return I18n.t("#{CHAVE}.unidades.seconds", count: 0) if partes.empty?

    partes.first(2).map { |unidade, quantos| I18n.t("#{CHAVE}.unidades.#{unidade}", count: quantos) }
          .to_sentence(two_words_connector: I18n.t("#{CHAVE}.e"))
  end

  # O rótulo de uma coluna da série: o primeiro dia do período, no formato do idioma.
  def coluna(comeco, grupo)
    formato = grupo == 'month' ? 'formato_mes' : 'formato_dia'
    comeco.to_date.strftime(I18n.t("#{CHAVE}.#{formato}"))
  end

  def nome_da_metrica(metrica)
    I18n.t("#{CHAVE}.metricas.#{metrica}")
  end

  # "Conversas resolvidas por pessoa", "Conversas por dia, Ana Souza".
  def titulo(pedido, por:, quem: nil)
    base = I18n.t("#{CHAVE}.titulo", metrica: nome_da_metrica(pedido.metrica), por: I18n.t("#{CHAVE}.por.#{por}"))
    quem.present? ? I18n.t("#{CHAVE}.titulo_de", titulo: base, quem: quem) : base
  end

  # O nome de um agente, caixa, etiqueta ou time.
  def nome(registro)
    registro.try(:name) || registro.try(:title)
  end
end
