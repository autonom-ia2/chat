# O painel de desempenho de um agente (#2251), calculado no servidor a partir da leitura guardada no banco:
# a ficha vigente (nomes e regras), as procuras lidas e, ao vivo, as mensagens das conversas lidas.
#
#   Autonomia::Desempenho::Painel.new(account:, sujeito_type: 'robo', sujeito_id: 1, visiveis: relation_ou_nil,
#                                     ve_valores: true).call('30')
#
# Devolve o painel de UM período no contrato v2 (o mesmo que a tela, o PDF e a planilha leem: os agregados + o
# catálogo + as procuras do período) ou nil quando o agente ainda não tem leitura. Os números são do que a pessoa vê
# (decisão do Rodrigo, 26/10, ESPEC 6.2): com `visiveis` (ContaDaIa.visiveis), procuras e mensagens saem só das
# conversas dessas caixas, e as sugestões (calculadas para a conta inteira) não vão; admin e quem vê todas as caixas
# (`visiveis` nil) recebem a conta inteira. Quem tem leitura mas não vê nenhuma das conversas recebe o painel vazio
# com a situação `sem_conversas`. `ve_valores` (Crm::ValorDeVenda.ve?) decide se o dinheiro vai (ver Visibilidade).
#
# O período termina no dia de `dados_ate` (a última mensagem lida), não hoje: antes da atualização automática, "7
# dias" são os 7 dias que a leitura cobre, e as mensagens ao vivo ficam na mesma janela.
class Autonomia::Desempenho::Painel
  PERIODOS = %w[7 30 90 tudo].freeze
  DIAS = { '7' => 7, '30' => 30, '90' => 90 }.freeze
  PADRAO = '30'.freeze
  FONTE = 'api'.freeze

  def initialize(account:, sujeito_type:, sujeito_id:, visiveis: nil, ve_valores: true)
    @account = account
    @sujeito_type = sujeito_type
    @sujeito_id = sujeito_id
    @visiveis = visiveis
    @ve_valores = ve_valores
  end

  def call(chave) # rubocop:disable Metrics/AbcSize
    chave = PERIODOS.include?(chave.to_s) ? chave.to_s : PADRAO
    return nil if ficha.nil? || todas.none? || dados_ate.nil?

    inicio, fim, anterior = self.class.intervalo(chave, fim_dos_dados, inicio_dos_dados)
    ocultas = ocultas_no_periodo(inicio, fim)
    return sem_conversas(chave, ocultas) if procuras.lista.empty?

    painel = agregador.painel(chave, inicio, fim, anterior: anterior, dados_ate: dados_ate, fonte: FONTE)
    painel = painel.merge('catalogo' => ficha.catalogo, 'procuras' => procuras_do_periodo(inicio, fim))
    Autonomia::Desempenho::Visibilidade.new(ocultas: @visiveis && ocultas, ve_valores: @ve_valores).aplicar(painel)
  end

  # [inicio, fim, anterior | nil]. Anterior só quando o dado cobre o período anterior inteiro.
  def self.intervalo(chave, fim, inicio_dos_dados)
    return [inicio_dos_dados, fim, nil] if chave == 'tudo'

    dias = DIAS.fetch(chave)
    inicio = [fim - (dias - 1), inicio_dos_dados].max
    ant_fim = inicio - 1
    ant_ini = ant_fim - (dias - 1)
    completo = ant_ini >= inicio_dos_dados && inicio == fim - (dias - 1)
    [inicio, fim, completo ? [ant_ini, ant_fim] : nil]
  end

  private

  def ficha
    return @ficha if defined?(@ficha)

    @ficha = Autonomia::Desempenho::Ficha.vigente(@account, @sujeito_type, @sujeito_id)
  end

  def fuso = ficha.configuracao.dig('meta', 'fuso')

  def procuras
    @procuras ||= Autonomia::Desempenho::Procuras.new(account: @account, sujeito_type: @sujeito_type, sujeito_id: @sujeito_id,
                                                      configuracao: ficha.configuracao, fuso: fuso, visiveis: @visiveis)
  end

  # Todas as procuras do agente, vistas ou não: dizem se há leitura e onde começam os dados (as datas do período são
  # as mesmas para todos).
  def todas = Autonomia::Desempenho::Procura.do_sujeito(@account, @sujeito_type, @sujeito_id)

  # Quantas procuras do período ficaram de fora por serem de caixa que a pessoa não vê (0 para quem vê todas).
  def ocultas_no_periodo(inicio, fim)
    return 0 if @visiveis.nil?

    faixa = fuso_da_ficha.parse(inicio.iso8601).beginning_of_day..fuso_da_ficha.parse(fim.iso8601).end_of_day
    todas.where(inicio_em: faixa).count - procuras_do_periodo(inicio, fim).size
  end

  def fuso_da_ficha = ActiveSupport::TimeZone[fuso.to_s] || ActiveSupport::TimeZone['UTC']

  def sem_conversas(chave, ocultas)
    { 'versao' => 2, 'vazio' => true,
      'meta' => { 'fonte' => FONTE, 'situacao' => 'sem_conversas', 'periodo' => { 'chave' => chave }, 'dados_ate' => dados_ate,
                  'base' => nil, 'visibilidade' => { 'escopo' => 'caixas', 'ocultas' => ocultas } } }
  end

  def leituras = Autonomia::Desempenho::Leitura.do_sujeito(@account, @sujeito_type, @sujeito_id)

  # 'AAAA-MM-DDTHH:MM' da última mensagem lida, no fuso da ficha.
  def dados_ate
    return @dados_ate if defined?(@dados_ate)

    ate = leituras.maximum(:lida_ate_em)
    @dados_ate = ate&.in_time_zone(fuso)&.strftime('%Y-%m-%dT%H:%M')
  end

  def fim_dos_dados = Autonomia::Desempenho::Conta.data(dados_ate)

  # O primeiro dia com procura, de todas as caixas (as de teste também contam, como no protótipo).
  def inicio_dos_dados
    @inicio_dos_dados ||= todas.minimum(:inicio_em).in_time_zone(fuso_da_ficha).to_date
  end

  def procuras_do_periodo(inicio, fim)
    ini = inicio.iso8601
    fi = fim.iso8601
    procuras.lista.select { |p| Autonomia::Desempenho::Conta.dia_de(p['inicio']).between?(ini, fi) }
  end

  def agregador
    Autonomia::Desempenho::Agregador.new(configuracao: ficha.configuracao, catalogo: ficha.catalogo, procuras: procuras.lista,
                                         fixos: fixos, inicio_dos_dados: inicio_dos_dados, fim_dos_dados: fim_dos_dados)
  end

  def fixos # rubocop:disable Metrics/AbcSize
    referencias = ficha.referencias
    {
      mensagens: mensagens, equipe_por_mes: mensagens.equipe_por_mes(fim_dos_dados),
      gerado_em: Time.current.in_time_zone(fuso).strftime('%Y-%m-%dT%H:%M'),
      anuncios_ligados: ficha.configuracao['anuncios_ligados'] == true, anuncios: ficha.configuracao['anuncios'],
      origem_nota: ficha.configuracao['origem_nota'], ticket: referencias['ticket'], confianca: referencias['confianca'],
      por_que: procuras.por_que, exemplos: procuras.exemplos(referencias['exemplos']), recomendacoes: method(:recomendacoes)
    }
  end

  def mensagens
    @mensagens ||= Autonomia::Desempenho::Mensagens.new(account: @account, sujeito_type: @sujeito_type, sujeito_id: @sujeito_id,
                                                        remetentes: ficha.configuracao['remetentes_do_agente'], fuso: fuso,
                                                        visiveis: @visiveis)
  end

  # As sugestões guardadas para este período, só se forem das mesmas datas e da mesma ficha. Elas são calculadas
  # com a conta inteira: quem vê só parte das caixas não as recebe.
  def recomendacoes(chave, inicio, fim)
    return [] if @visiveis

    cache = Autonomia::Desempenho::Recomendacao.do_sujeito(@account, @sujeito_type, @sujeito_id)
                                               .find_by(periodo: chave, inicio: inicio, fim: fim, versao_ficha: ficha.versao)
    cache ? cache.cartoes : []
  end
end
