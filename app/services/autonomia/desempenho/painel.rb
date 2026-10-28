# O painel de desempenho de um agente (#2251), calculado no servidor a partir da leitura guardada no banco:
# a ficha vigente (nomes e regras), as procuras lidas e, ao vivo, as mensagens das conversas lidas.
#
#   Autonomia::Desempenho::Painel.new(account:, sujeito_type: 'robo', sujeito_id: 1, visiveis: relation_ou_nil,
#                                     ve_valores: true).call('30')
#
# Devolve o painel de UM período no contrato v2 (o mesmo que a tela, o PDF e a planilha leem: os agregados + o
# catálogo + as procuras do período) ou nil quando o agente ainda não tem leitura. Os números são do que a pessoa vê
# (decisão do Rodrigo, 26/10, ESPEC 6.2): com `visiveis` (ContaDaIa.visiveis), procuras e mensagens saem só das
# conversas dessas caixas, e as sugestões e o ticket (calculados para a conta inteira) não vão; admin e quem vê todas
# as caixas (`visiveis` nil) recebem a conta inteira. Quem tem leitura mas não vê nenhuma das conversas recebe o
# painel vazio com a situação `sem_conversas`. `ve_valores` (Crm::ValorDeVenda.ve?) decide se o dinheiro vai.
#
# Do banco sai só o período e o anterior (procuras por `inicio_em`, mensagens por `created_at`); o que é do histórico
# (início dos dados, primeira procura de cada conversa, equipe por mês) tem consulta própria. A lista de procuras do
# período vai inteira até LIMITE_DA_LISTA; acima disso, as mais recentes, com `meta.lista` dizendo quantas são.
#
# O fuso é um só em tudo: o da conta (Crm::Timezone::Resolver); sem ele, o da ficha; sem nome válido, o padrão.
#
# O período termina no dia de `dados_ate` (a última mensagem lida), não hoje: "7 dias" são os 7 dias que a leitura
# cobre, e as mensagens ao vivo ficam na mesma janela. Com a leitura automática ligada (#2301), `dados_ate` é o "Lido
# até" quando ele vem antes: com conversas pendentes, os dias depois dele têm só parte das conversas lidas e mostrariam
# uma queda que não existe.
class Autonomia::Desempenho::Painel
  PERIODOS = %w[7 30 90 tudo].freeze
  DIAS = { '7' => 7, '30' => 30, '90' => 90 }.freeze
  PADRAO = '30'.freeze
  FONTE = 'api'.freeze
  LIMITE_DA_LISTA = 5_000

  def initialize(account:, sujeito_type:, sujeito_id:, visiveis: nil, ve_valores: true)
    @account = account
    @sujeito_type = sujeito_type
    @sujeito_id = sujeito_id
    @pedidas = visiveis
    @ve_valores = ve_valores
  end

  def call(chave)
    chave = PERIODOS.include?(chave.to_s) ? chave.to_s : PADRAO
    return nil unless com_leitura?

    preparar(chave)
    return sem_conversas(chave) if @visiveis && !todas.exists?(conversation_id: @visiveis.select(:id))

    painel = com_leitura_automatica(agregador.painel(chave, @inicio, @fim, anterior: @anterior, dados_ate: ate_onde_leu, fonte: FONTE))
    Autonomia::Desempenho::Visibilidade.new(ocultas: @visiveis && ocultas_no_periodo, ve_valores: @ve_valores)
                                       .aplicar(com_lista(painel))
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

  # A situação do painel sem nenhuma procura do agente. Com a leitura automática ligada para ele (#2301): `lendo` antes
  # da primeira rodada e durante uma, a parada da última rodada, ou `sem_conversas` quando ela leu e não achou nada.
  # Sem ela, `leitura_desligada`.
  def self.situacao_sem_procuras(account, sujeito_type, sujeito_id)
    ficha = Autonomia::Desempenho::Ficha.vigente(account, sujeito_type, sujeito_id)
    return 'leitura_desligada' unless Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada? && ficha&.chave_de_leitura.present?

    ultima = Autonomia::Desempenho::Rodada.do_sujeito(account, sujeito_type, sujeito_id).recentes.first
    return 'lendo' if ultima.nil? || ultima.status == 'rodando'

    Autonomia::Desempenho::Rodada::PARADAS.include?(ultima.status) ? ultima.status : 'sem_conversas'
  end

  # O nome IANA do fuso: o da conta, senão o da ficha, senão o padrão da plataforma. Nunca um nome inválido.
  def self.fuso_de(account, ficha)
    nome = Crm::Timezone::Resolver.new(account: account).name ||
           [ficha&.configuracao&.dig('meta', 'fuso')].find { |candidato| ActiveSupport::TimeZone[candidato.to_s] } ||
           Crm::Timezone::Resolver.default_timezone
    ActiveSupport::TimeZone[nome].tzinfo.name
  end

  private

  def com_leitura? = ficha.present? && todas.exists? && dados_ate.present?

  # A leitura automática vale para este agente: a ENV ligada e a ficha com a chave de leitura. Desligada, somem o
  # "Lido até", a situação e os avisos da leitura, e nenhuma rodada nova roda. Os números continuam os gravados, com
  # o que a leitura automática já regravou: ela troca as procuras da carga pelas novas e move a última mensagem lida
  # ("Dados até"). Desligar a ENV não devolve a carga; a volta dos dados é o pacote de volta da conta, por psql.
  def automatica? = @automatica

  # As datas do período e o que depende delas, refeito a cada chamada.
  def preparar(chave)
    @automatica = Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada? && ficha.chave_de_leitura.present?
    @lido_ate = calcular_lido_ate
    @visiveis = so_parte_das_caixas? ? @pedidas : nil
    @inicio, @fim, @anterior = self.class.intervalo(chave, fim_dos_dados, inicio_dos_dados)
    @procuras = @procuras_do_periodo = @mensagens = @recomendacoes_de = nil
  end

  # O que a leitura automática (#2301) acrescenta à meta:
  # - `lido_ate`: o corte da última rodada que leu (Rodada.leram) quando ela não deixou pendente; com pendentes, o
  #   momento antes da mensagem pendente mais antiga (sem ela, o piso da rodada), no fuso: tudo antes disso foi lido;
  # - `situacao`: `sem_ia`, `chave_recusada`, `teto` ou `erro` quando a última rodada parou por isso (com uma rodada
  #   rodando agora, nenhuma: a parada de antes pode já não valer);
  # - `pendentes`: quantas conversas a última rodada que leu deixou para a próxima (o "Lido até" para antes delas);
  # - `nao_lidas`: quantas conversas do período a leitura automática deixou como não lidas (grandes demais ou com erro
  #   repetido): a última mensagem delas cai no período, e as de teste ficam de fora. Os números delas são os da última
  #   leitura, quando houve uma;
  # - `instrucao_mudou`: a instrução do agente mudou depois da chave de leitura (nil para o robô de outro sistema);
  # - `recomendacoes_de`: as datas das sugestões quando elas são de outro período.
  # Tudo isso só com a leitura automática ligada para o agente (`automatica?`). Os avisos vão também em `avisos`, para
  # as exportações dizerem o mesmo que a tela.
  def com_leitura_automatica(painel)
    meta = painel['meta'].merge('lido_ate' => lido_ate, 'instrucao_mudou' => instrucao_mudou?, 'recomendacoes_de' => @recomendacoes_de,
                                'nao_lidas' => nao_lidas, 'pendentes' => pendentes)
    parada = ultima_rodada&.status if automatica?
    meta['situacao'] ||= parada if Autonomia::Desempenho::Rodada::PARADAS.include?(parada)
    painel.merge('meta' => meta, 'avisos' => Array(painel['avisos']) + avisos_da_leitura(meta, parada))
  end

  # Os avisos da leitura automática para as exportações (o PDF e a planilha), na ordem da tela.
  def avisos_da_leitura(meta, parada)
    [(["leitura_#{parada}", {}] if Autonomia::Desempenho::Rodada::PARADAS.include?(parada)),
     (['leitura_pendentes', { 'n' => meta['pendentes'] }] if meta['pendentes'].positive?),
     (['leitura_nao_lidas', { 'n' => meta['nao_lidas'] }] if meta['nao_lidas'].positive?),
     (['leitura_instrucao', {}] if meta['instrucao_mudou'])].compact.map { |id, valores| { 'id' => id, 'valores' => valores } }
  end

  def rodadas = Autonomia::Desempenho::Rodada.do_sujeito(@account, @sujeito_type, @sujeito_id).recentes

  # A última rodada que fechou, ou nil com uma rodando agora.
  def ultima_rodada
    rodada = rodadas.first
    rodada unless rodada.nil? || rodada.status == 'rodando'
  end

  attr_reader :lido_ate

  def calcular_lido_ate
    rodada = rodadas.leram.first if automatica?
    return nil if rodada.nil?

    ate = rodada.conversas_pendentes.zero? ? rodada.corte_em : antes_da_pendente(rodada)
    ate.in_time_zone(fuso).strftime('%Y-%m-%dT%H:%M')
  end

  # Até onde os números valem: a última mensagem lida, ou o "Lido até" quando ele vem antes.
  def ate_onde_leu = [dados_ate, lido_ate].compact.min

  # Só as conversas que a pessoa vê, com a última mensagem dentro do período e sem procura de teste.
  def nao_lidas
    return 0 unless automatica?

    escopo = leituras.where(status: 'nao_lida', lote: Autonomia::Desempenho::LeituraAutomatica::Gravacao::LOTE,
                            lida_ate_em: faixa_em_horas(@inicio..@fim))
                     .where.not(conversation_id: todas.where(teste: true).select(:conversation_id))
    escopo = escopo.where(conversation_id: @visiveis.select(:id)) if @visiveis
    escopo.count
  end

  # As que a última rodada fechada deixou para a próxima (a `teto` que não leu nada também deixa), mesmo com outra
  # rodando agora. A rodada conta as da conta inteira: quem vê só parte das caixas não recebe o número. A `erro` de
  # RodadaComErro não conta nada (fica 0).
  def pendentes
    return 0 unless automatica? && @visiveis.nil?

    rodadas.where.not(status: 'rodando').first&.conversas_pendentes.to_i
  end

  # A rodada grava a mensagem pendente mais antiga ao fechar; sem ela, o piso da rodada.
  def antes_da_pendente(rodada) = rodada.pendente_desde ? rodada.pendente_desde - 1.second : rodada.piso_em

  # Só com a leitura automática: desligada, ninguém lê com a chave, e o aviso não tem o que dizer.
  def instrucao_mudou?
    return nil unless automatica? && @sujeito_type == 'agente' && ficha.instrucao_hash.present?

    Autonomia::Desempenho::Ficha.hash_da_instrucao(@account, @sujeito_type, @sujeito_id) != ficha.instrucao_hash
  end

  def ficha
    return @ficha if defined?(@ficha)

    @ficha = Autonomia::Desempenho::Ficha.vigente(@account, @sujeito_type, @sujeito_id)
  end

  # Quem vê todas as conversas lidas (mesmo por uma função personalizada) recebe a conta inteira.
  def so_parte_das_caixas?
    !@pedidas.nil? && todas.where.not(conversation_id: @pedidas.select(:id)).exists?
  end

  def fuso = @fuso ||= self.class.fuso_de(@account, ficha)
  def zona = ActiveSupport::TimeZone[fuso]

  # A configuração da ficha com o fuso único no lugar do dela (o agregador lê o fuso daí).
  def configuracao = @configuracao ||= ficha.configuracao.deep_merge('meta' => { 'fuso' => fuso })

  # Do primeiro dia do período anterior (ou do período) até o fim, em datas do fuso.
  def faixa = (@anterior ? @anterior.first : @inicio)..@fim
  def faixa_em_horas(datas) = zona.parse(datas.first.iso8601).beginning_of_day..zona.parse(datas.last.iso8601).end_of_day

  def procuras
    @procuras ||= Autonomia::Desempenho::Procuras.new(account: @account, sujeito_type: @sujeito_type, sujeito_id: @sujeito_id,
                                                      configuracao: configuracao, fuso: fuso, visiveis: @visiveis,
                                                      faixa: faixa_em_horas(faixa))
  end

  # Todas as procuras do agente, vistas ou não: dizem se há leitura e onde começam os dados (as datas do período são
  # as mesmas para todos).
  def todas = Autonomia::Desempenho::Procura.do_sujeito(@account, @sujeito_type, @sujeito_id)

  # Quantas procuras do período ficaram de fora por serem de caixa que a pessoa não vê.
  def ocultas_no_periodo
    todas.where(inicio_em: faixa_em_horas(@inicio..@fim)).count - procuras_do_periodo.size
  end

  def sem_conversas(chave)
    { 'versao' => 2, 'vazio' => true,
      'meta' => { 'fonte' => FONTE, 'situacao' => 'sem_conversas', 'periodo' => { 'chave' => chave }, 'dados_ate' => ate_onde_leu,
                  'base' => nil, 'visibilidade' => { 'escopo' => 'caixas', 'ocultas' => ocultas_no_periodo } } }
  end

  def leituras = Autonomia::Desempenho::Leitura.do_sujeito(@account, @sujeito_type, @sujeito_id)

  # 'AAAA-MM-DDTHH:MM' da última mensagem lida, no fuso.
  def dados_ate
    return @dados_ate if defined?(@dados_ate)

    ate = leituras.maximum(:lida_ate_em)
    @dados_ate = ate&.in_time_zone(fuso)&.strftime('%Y-%m-%dT%H:%M')
  end

  def fim_dos_dados = Autonomia::Desempenho::Conta.data(ate_onde_leu)

  # O primeiro dia com procura, de todas as caixas (as de teste também contam, como no protótipo).
  def inicio_dos_dados
    @inicio_dos_dados ||= todas.minimum(:inicio_em).in_time_zone(fuso).to_date
  end

  def procuras_do_periodo
    ini = @inicio.iso8601
    fi = @fim.iso8601
    @procuras_do_periodo ||= procuras.lista.select { |p| Autonomia::Desempenho::Conta.dia_de(p['inicio']).between?(ini, fi) }
  end

  # O catálogo e a lista do período; acima do teto, só as mais recentes, e `meta.lista` diz quantas são.
  def com_lista(painel)
    lista = procuras_do_periodo
    return painel.merge('catalogo' => ficha.catalogo, 'procuras' => lista) if lista.size <= LIMITE_DA_LISTA

    recentes = lista.max_by(LIMITE_DA_LISTA) { |p| [p['inicio'], p['conversa'], p['procura']] }
                    .sort_by { |p| [p['conversa'], p['procura']] }
    painel.merge('catalogo' => ficha.catalogo, 'procuras' => recentes,
                 'meta' => painel['meta'].merge('lista' => { 'total' => lista.size, 'mostradas' => recentes.size }))
  end

  def agregador
    Autonomia::Desempenho::Agregador.new(configuracao: configuracao, catalogo: ficha.catalogo, procuras: procuras.lista,
                                         fixos: fixos, inicio_dos_dados: inicio_dos_dados, fim_dos_dados: fim_dos_dados)
  end

  def fixos # rubocop:disable Metrics/AbcSize
    referencias = ficha.referencias
    {
      mensagens: mensagens, equipe_por_mes: mensagens.equipe_por_mes(fim_dos_dados), primeiras: procuras.primeiras,
      gerado_em: Time.current.in_time_zone(fuso).strftime('%Y-%m-%dT%H:%M'),
      anuncios_ligados: configuracao['anuncios_ligados'] == true, anuncios: configuracao['anuncios'],
      origem_nota: configuracao['origem_nota'], ticket: referencias['ticket'], confianca: referencias['confianca'],
      por_que: procuras.por_que, exemplos: procuras.exemplos(referencias['exemplos']), recomendacoes: method(:recomendacoes)
    }
  end

  def mensagens
    @mensagens ||= Autonomia::Desempenho::Mensagens.new(account: @account, sujeito_type: @sujeito_type, sujeito_id: @sujeito_id,
                                                        remetentes: configuracao['remetentes_do_agente'], fuso: fuso,
                                                        visiveis: @visiveis, faixa: faixa)
  end

  # As sugestões guardadas para este período, da mesma ficha. Elas são calculadas com a conta inteira: quem vê só parte
  # das caixas não as recebe. Sem leitura automática, só as das mesmas datas. Com ela (#2301), as datas andam todo dia
  # e as sugestões nem sempre acompanham: sem as do período exato, vão as últimas do mesmo período, com as datas delas
  # em `meta.recomendacoes_de` (gerar as do período é o #2320).
  def recomendacoes(chave, inicio, fim)
    return [] if @visiveis

    guardadas = Autonomia::Desempenho::Recomendacao.do_sujeito(@account, @sujeito_type, @sujeito_id)
                                                   .where(periodo: chave, versao_ficha: ficha.versao)
    guardadas = guardadas.where(inicio: inicio, fim: fim) unless automatica? && rodadas.leram.exists?
    cache = guardadas.first
    return [] if cache.nil?

    @recomendacoes_de = { 'inicio' => cache.inicio.iso8601, 'fim' => cache.fim.iso8601 } unless cache.inicio == inicio && cache.fim == fim
    cache.cartoes
  end
end
