# `ranking` do relatório do Guia (#3158): a métrica de cada agente, caixa, etiqueta ou time no período, do maior
# para o menor. Portado do `summary` do `Captain::Copilot::ReportService`: os `*SummaryBuilder` são os mesmos das
# listas da tela Relatórios.
#
# Ficam só os que tiveram atividade no período; os outros são contados (`sem_atividade`), para "quem não
# resolveu nenhuma?" ser um número, e não um palpite.
class Autonomia::Guide::Relatorio::Ranking
  Rotulos = Autonomia::Guide::Relatorio::Rotulos
  BUILDERS = {
    'agente' => V2::Reports::AgentSummaryBuilder, 'caixa' => V2::Reports::InboxSummaryBuilder,
    'etiqueta' => V2::Reports::LabelSummaryBuilder, 'time' => V2::Reports::TeamSummaryBuilder
  }.freeze
  # A coluna do resumo que cada métrica lê. As outras métricas não têm resumo por agente na tela.
  COLUNAS = {
    'conversations_count' => :conversations_count, 'resolutions_count' => :resolved_conversations_count,
    'avg_first_response_time' => :avg_first_response_time, 'avg_resolution_time' => :avg_resolution_time,
    'reply_time' => :avg_reply_time
  }.freeze
  # O resumo por etiqueta dá 0 para média sem eventos: zero ali é "nada medido".
  TEMPOS_DA_ETIQUETA = %i[avg_first_response_time avg_resolution_time avg_reply_time].freeze

  def initialize(pedido)
    @pedido = pedido
    @coluna = COLUNAS.fetch(pedido.metrica) do
      raise Autonomia::Guide::Relatorio::Recusado,
            "ranking só tem #{COLUNAS.keys.join(', ')}. Para #{pedido.metrica}, peça serie ou resumo de um(a) #{pedido.por} pelo id."
    end
  end

  def call
    { relatorio: 'ranking', metrica: @pedido.metrica, por: @pedido.por, de: @pedido.de.iso8601, ate: @pedido.ate.iso8601,
      fuso: @pedido.fuso, linhas: linhas, sem_atividade: todas.size - ativas.size,
      grafico_dados: (grafico if @pedido.grafico?) }
  end

  private

  def todas
    @todas ||= BUILDERS.fetch(@pedido.por)
                       .new(account: @pedido.account, params: @pedido.params_do_builder.merge(type: @pedido.tipo_do_builder.to_sym))
                       .build.map { |linha| etiqueta_sem_zero(linha) }
  end

  def etiqueta_sem_zero(linha)
    return linha unless @pedido.por == 'etiqueta'

    linha.merge(linha.slice(*TEMPOS_DA_ETIQUETA).transform_values { |valor| valor.to_f.nonzero? })
  end

  # Com conversa, resolvida ou tempo medido no período, ordenadas pela métrica; quem não tem valor vai por último.
  def ativas
    @ativas ||= todas.select { |linha| ativa?(linha) }
                     .sort_by { |linha| linha[@coluna].nil? ? [1, 0] : [0, -linha[@coluna].to_f] }
  end

  def ativa?(linha)
    linha[:conversations_count].to_i.positive? || linha[:resolved_conversations_count].to_i.positive? ||
      linha[:avg_first_response_time].present? || linha[:avg_reply_time].present?
  end

  def nomes
    @nomes ||= case @pedido.por
               when 'agente' then @pedido.account.users.pluck(:id, :name).to_h
               when 'caixa' then @pedido.account.inboxes.pluck(:id, :name).to_h
               when 'time' then @pedido.account.teams.pluck(:id, :name).to_h
               else {}
               end
  end

  def linhas
    ativas.map do |linha|
      valor = linha[@coluna]
      base = { nome: linha[:name] || nomes[linha[:id]], id: linha[:id] }
      @pedido.media? ? base.merge(segundos: valor&.to_f&.round, tempo: Rotulos.tempo(valor)) : base.merge(valor: valor)
    end
  end

  # Uma barra por linha com valor, na ordem do ranking. Tempo em minutos, com uma casa.
  def grafico
    barras = ativas.reject { |linha| linha[@coluna].nil? }.map do |linha|
      valor = linha[@coluna]
      { rotulo: linha[:name] || nomes[linha[:id]], valor: @pedido.media? ? (valor.to_f / 60).round(1) : valor }
    end
    Autonomia::Guide::Grafico.montar(modo: 'ranking', titulo: Rotulos.titulo(@pedido, por: @pedido.por),
                                     medida: Rotulos.nome_da_metrica(@pedido.metrica), pedido: @pedido, barras: barras)
  end
end
