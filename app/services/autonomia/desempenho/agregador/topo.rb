# Os 8 números do topo e a evolução do painel de desempenho (#2251), como no protótipo.
module Autonomia::Desempenho::Agregador::Topo
  DIAS_SEMANA = 7

  private

  # A base (n de m) vai junto do número e do anterior, para a comparação de uma taxa ser em pontos.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def kpis(nums, ant, tempo, tempo_ant)
    sem = nums['precisavam'].size - nums['tiveram'].size
    sem_ant = ant && (ant['precisavam'].size - ant['tiveram'].size)
    composicao = Autonomia::Desempenho::Conta.contagem(nums['fech'].map { |p| p['resultado_id'] })
                                             .map { |id, v| { 'id' => id, 'nome' => cat.dig('resultados', id, 'nome'), 'valor' => v } }
    [
      kpi('procuras', nums['procuras'].size, ant && ant['procuras'].size, 'volume', 'subir'),
      kpi('conversas', nums['conversas'].size, ant && ant['conversas'].size, 'volume', 'subir'),
      kpi('compra', nums['compra'].size, ant && ant['compra'].size, 'preparo', 'subir',
          base: base_kpi(nums, 'compra', 'procuras'), anterior_base: ant && base_kpi(ant, 'compra', 'procuras')),
      kpi('fecharam', nums['fech'].size, ant && ant['fech'].size, 'resultado', 'subir',
          base: base_kpi(nums, 'fech', 'compra'), composicao: composicao, anterior_base: ant && base_kpi(ant, 'fech', 'compra')),
      kpi('duvidas_resolvidas', nums['resolvidas'].size, ant && ant['resolvidas'].size, 'resultado', 'subir',
          base: base_kpi(nums, 'resolvidas', 'duvidas'), anterior_base: ant && base_kpi(ant, 'resolvidas', 'duvidas')),
      kpi('sem_pessoa', sem, sem_ant, 'alerta', 'descer',
          base: base_kpi(nums, sem, 'precisavam'), anterior_base: ant && base_kpi(ant, sem_ant, 'precisavam')),
      kpi('perdas_evitaveis', nums['perdas'].size, ant && ant['perdas'].size, 'alerta', 'descer',
          base: base_kpi(nums, 'perdas', 'compra'), anterior_base: ant && base_kpi(ant, 'perdas', 'compra')),
      kpi('tempo_resposta', tempo['mediana_seg'], tempo_ant && tempo_ant['mediana_seg'], 'tempo', 'descer',
          formato: 'segundos', extra: { 'p90' => tempo['p90_seg'], 'medidas' => tempo['medidas'] })
    ]
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def kpi(id, valor, anterior, cor, melhor, base: nil, composicao: nil, formato: 'numero', extra: nil, anterior_base: nil) # rubocop:disable Metrics/ParameterLists
    { 'id' => id, 'valor' => valor, 'anterior' => anterior, 'formato' => formato, 'cor' => cor, 'melhor' => melhor,
      'base' => base, 'anterior_base' => anterior_base, 'composicao' => composicao, 'extra' => extra }
  end

  # `parte`: o nome de uma lista dos números ou já a contagem.
  def base_kpi(numeros, parte, total)
    { 'n' => parte.is_a?(String) ? numeros[parte].size : parte, 'm' => numeros[total].size }
  end

  # [[inicio, fim]] de cada dia, ou de cada semana (segunda a domingo) cortada pelo período.
  def baldes(inicio, fim, unidade)
    return (inicio..fim).map { |dia| [dia, dia] } if unidade == 'dia'

    segunda = inicio - (inicio.cwday - 1)
    out = []
    while segunda <= fim
      out << [[segunda, inicio].max, [segunda + (DIAS_SEMANA - 1), fim].min]
      segunda += DIAS_SEMANA
    end
    out
  end

  def evolucao(lista, inicio, fim, unidade, dados_ate)
    primeira = primeira_procura_da_conversa
    pontos = baldes(inicio, fim, unidade).map do |b_inicio, b_fim|
      ini = b_inicio.iso8601
      fi = b_fim.iso8601
      dentro = lista.select { |p| dia_de(p['inicio']).between?(ini, fi) }
      # Semana cortada pelo começo ou pelo fim do período, ou o dia/semana ainda em andamento.
      cortada = unidade == 'semana' && (b_fim - b_inicio).to_i + 1 < DIAS_SEMANA
      ponto(dentro, ini, fi, primeira.count { |_conversa, dia| dia.between?(ini, fi) }, cortada || dia_de(dados_ate) <= fi)
    end
    { 'unidade' => unidade, 'pontos' => pontos }
  end

  # {conversa => dia da primeira procura}. O painel do servidor manda pronto (`fixos[:primeiras]`, do histórico
  # inteiro), porque carrega do banco só o período e o anterior; sem ele, sai das procuras recebidas, como no protótipo.
  def primeira_procura_da_conversa
    return fixos[:primeiras] if fixos[:primeiras]

    todas.reject { |p| p['teste'] }.each_with_object({}) { |p, primeira| primeira[p['conversa']] ||= dia_de(p['inicio']) }
  end

  def ponto(dentro, ini, fim, novas, parcial) # rubocop:disable Metrics/CyclomaticComplexity
    com = dentro.count { |p| tipo_origem(p) == 'anuncio' }
    { 'inicio' => ini, 'fim' => fim, 'procuras' => dentro.size, 'conversas_novas' => novas,
      'compra' => dentro.count { |p| eh_compra?(p) }, 'fecharam' => dentro.count { |p| eh_compra?(p) && fechou?(p) },
      'precisavam_pessoa' => dentro.count { |p| p['precisava_pessoa'] },
      'tiveram_pessoa' => dentro.count { |p| p['precisava_pessoa'] && p['teve_pessoa'] },
      'com_anuncio' => com, 'sem_anuncio' => dentro.size - com, 'parcial' => parcial }
  end
end
