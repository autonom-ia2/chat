# O que o modelo pediu à `relatorio_de_atendimento`, conferido e traduzido para os builders v2 (#3158).
#
# As datas são dias de calendário no fuso de relatório da conta, como a tela Relatórios escolhe: `de` é o
# primeiro dia e `ate` o último, incluído. Cada dia começa à meia-noite daquele fuso, com o deslocamento da
# própria data (horário de verão), igual ao Copilot.
class Autonomia::Guide::Relatorio::Pedido
  TIPOS = %w[resumo serie ranking].freeze
  # O nome que o Guia usa -> o `type` dos builders.
  POR = { 'conta' => 'account', 'agente' => 'agent', 'caixa' => 'inbox', 'etiqueta' => 'label', 'time' => 'team' }.freeze
  AGRUPAR = { 'dia' => 'day', 'semana' => 'week', 'mes' => 'month' }.freeze
  METRICAS = Reports::ReportMetricRegistry::METRICS.keys.map(&:to_s).freeze
  # A série vai para um gráfico de colunas no painel de 320 px: acima disto, agrupa no período seguinte.
  MAX_PONTOS = 31

  # `fim` é a meia-noite depois do último dia.
  attr_reader :account, :tipo, :metrica, :por, :de, :ate, :agrupar, :fuso, :inicio, :fim

  def initialize(account:, params:)
    @account = account
    @fuso = account.report_time_zone
    @tipo = escolha(params['tipo'], TIPOS, 'tipo')
    @metrica = escolha(params['metrica'], METRICAS, 'metrica')
    @por = escolha(params['por'].presence || 'conta', POR.keys, 'por')
    @id = params['id'].to_s.strip.presence
    @grafico = params['grafico'] == true
    ler_datas(params['de'], params['ate'])
    @agrupar = agrupamento(params['agrupar'].presence || 'dia')
    conferir!
  end

  def grafico? = @grafico

  def media?
    Reports::ReportMetricRegistry.fetch(metrica).average?
  end

  def tipo_do_builder = POR.fetch(por)

  def grupo_do_builder = AGRUPAR.fetch(agrupar)

  # O agrupamento foi trocado porque o período passou de 31 pontos.
  def reagrupado? = @reagrupado == true

  # O id que os builders recebem. A etiqueta pode vir pelo nome, como a pessoa fala.
  def id_do_builder
    return nil if por == 'conta'
    return etiqueta&.id if por == 'etiqueta'

    @id.to_i
  end

  # O registro que o relatório descreve ("agente Ana Souza"), ou nil para a conta. Achado nesta conta.
  def alvo
    @alvo ||= case por
              when 'conta' then nil
              when 'etiqueta' then etiqueta
              else { 'agente' => account.users, 'caixa' => account.inboxes, 'time' => account.teams }.fetch(por).find_by(id: @id.to_i)
              end
  end

  # Os parâmetros que a tela Relatórios manda aos builders. O nome do fuso agrupa os períodos; o deslocamento é
  # para os builders que só aceitam deslocamento.
  def params_do_builder
    deslocamento = ActiveSupport::TimeZone[fuso].now.utc_offset / 3600.0
    { since: inicio, until: fim, business_hours: false, timezone: fuso, timezone_offset: deslocamento }
  end

  private

  def escolha(valor, opcoes, nome)
    texto = valor.to_s.strip
    return texto if opcoes.include?(texto)

    raise Autonomia::Guide::Relatorio::Recusado, "#{nome} precisa ser um destes: #{opcoes.join(', ')}."
  end

  def ler_datas(primeiro, ultimo)
    @de = Date.iso8601(primeiro.to_s)
    @ate = Date.iso8601(ultimo.to_s)
    @inicio = @de.in_time_zone(fuso)
    @fim = @ate.next_day.in_time_zone(fuso)
  rescue Date::Error
    raise Autonomia::Guide::Relatorio::Recusado, 'de e ate precisam ser datas no formato AAAA-MM-DD.'
  end

  # Até 31 dias por dia; acima disso por semana; acima de 31 semanas por mês.
  def agrupamento(pedido)
    grupo = escolha(pedido, AGRUPAR.keys, 'agrupar')
    return grupo unless tipo == 'serie'

    dias = (@ate - @de).to_i + 1
    novo = grupo
    novo = 'semana' if novo == 'dia' && dias > MAX_PONTOS
    novo = 'mes' if novo == 'semana' && (dias / 7.0).ceil > MAX_PONTOS
    @reagrupado = novo != grupo
    novo
  end

  def conferir!
    recusar('de não pode ser depois de ate.') if @de > @ate
    recusar('ranking precisa de por: agente, caixa, etiqueta ou time.') if tipo == 'ranking' && por == 'conta'
    conferir_alvo! unless tipo == 'ranking' || por == 'conta'
  end

  def conferir_alvo!
    recusar("Para #{tipo} de um(a) #{por}, mande o id que veio da leitura.") if @id.nil?
    recusar("Não achei #{por} #{@id} nesta conta.") if alvo.nil?
  end

  def recusar(motivo)
    raise Autonomia::Guide::Relatorio::Recusado, motivo
  end

  # Pelo id lido ou pelo nome da etiqueta, como a pessoa escreveu.
  def etiqueta
    @etiqueta ||= begin
      numero = Integer(@id.to_s, exception: false)
      (numero && account.labels.find_by(id: numero)) || account.labels.find_by(title: @id.to_s.downcase)
    end
  end
end
