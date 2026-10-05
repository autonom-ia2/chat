# `planejar_tarefa` (#936): da receita à tarefa `amostra_pronta`, SEM escrever nada na conta.
#
# Lê os alvos com a permissão da pessoa, congela a lista (só referências), prepara os 10 primeiros
# como o lote faria e mostra o antes e o depois de cada um. Todo corpo da amostra passa pela
# conferência inteira da ação, inclusive por dentro dos campos JSON (`Conferencia#por_dentro`, #932):
# um corpo errado aqui seria gravado 500 vezes.
#
# Recusa, com o motivo: quem não administra, ação sem desfazer (`SEM_DESFAZER` ou `x-sem-volta`),
# mais de 5.000 itens, cota do Jev que não cabe e corpo fora do formato.
class Autonomia::Guide::Tarefas::Amostra
  Recusada = ::Autonomia::Guide::Tarefas::Recusada
  Tarefa = ::Autonomia::Guide::Tarefa
  TAMANHO = 10
  # O teto do custo é o dobro da estimativa (AC-TL13).
  FOLGA_DO_TETO = 2
  ESPERA_ENTRE_LOTES = 2

  def initialize(contexto:, receita:)
    @contexto = contexto
    @receita = ::Autonomia::Guide::Tarefas::Receita.new(receita)
  end

  def planejar
    conferir_pedido!
    alvos = listar!
    inicio = relogio
    preparados = preparar(alvos.first(TAMANHO).pluck('id'))
    pares = preparados.map { |preparado| par(preparado) }
    criar(alvos, pares, preparados, relogio - inicio)
  end

  private

  def conferir_pedido!
    raise Recusada, I18n.t('autonomia.guide.admin_only') unless @contexto.administrador?
    raise Recusada, "a receita não está completa: #{@receita.problemas.join('; ')}" if @receita.problemas.any?
    raise Recusada, "#{@receita.acao} não existe; o que existe é: #{vizinhas}" unless acoes.catalogo.include?(@receita.acao)
    return if acoes.desfazivel?(@receita.acao)

    raise Recusada, "#{@receita.acao} não tem desfazer; mensagem em massa é campanha, e o resto vai por propor_acao"
  end

  def listar!
    alvos = ::Autonomia::Guide::Tarefas::Alvos.new(consulta: @contexto.consulta, receita: @receita).listar
    raise Recusada, "nenhum registro de #{@receita.recurso} passa pelo filtro; nada a fazer" if alvos.empty?
    raise Recusada, "passa de #{Tarefa::MAX_ITENS} registros; filtre ou divida em partes" if alvos.size > Tarefa::MAX_ITENS
    raise Recusada, 'um registro sem número de id não tem como ser apontado' if alvos.any? { |alvo| numero(alvo['id']).nil? }

    conferir_cota!(alvos.size)
    alvos
  end

  def conferir_cota!(total)
    return unless @receita.usa_jev?

    restante = ::Autonomia::Guide::Tarefas::Jev.restante(@contexto.account)
    return if total <= restante

    raise Recusada, "a classificação usaria #{total} perguntas ao Jev, e a conta tem #{restante} neste mês"
  end

  def preparar(ids)
    @preparo = ::Autonomia::Guide::Tarefas::Preparo.new(contexto: @contexto, receita: @receita)
    @preparo.preparar(ids)
  rescue ::Autonomia::Guide::Tarefas::Preparo::CotaEsgotada
    raise Recusada, 'a cota mensal de classificações do Jev acabou'
  rescue ::Autonomia::Guide::Tarefas::Gerador::Falhou
    raise Recusada, 'não consegui escrever os valores novos agora; tente de novo daqui a pouco'
  end

  # O antes e o depois de um item, com o corpo já conferido como na execução.
  def par(preparado)
    rotulo = ::Autonomia::Guide::Tarefas::Preparo.rotulo(preparado.registro, preparado.id)
    return { 'ref' => rotulo, 'pulado' => preparado.motivo } if preparado.motivo
    raise Recusada, "o corpo de #{rotulo} faz algo sem desfazer (sai da conta); isso não vira tarefa" unless
      acoes.desfazivel?(@receita.acao, preparado.dados)

    acoes.conferir!(@receita.acao, preparado.dados)
    depois = conferencia(preparado).valores
    { 'ref' => rotulo, 'antes' => depois.keys.index_with { |campo| preparado.registro[campo] }, 'depois' => depois }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    raise Recusada, "o corpo de #{rotulo} não passou na conferência:\n#{e.message}"
  end

  def conferencia(preparado)
    ::Autonomia::Guide::Formatos::Conferencia.new(@receita.acao, preparado.dados[:corpo], conta: @contexto.account)
  end

  def criar(alvos, pares, preparados, duracao)
    custo = estimar_custo(preparados, alvos.size)
    Tarefa.transaction do
      tarefa = Tarefa.create!(account: @contexto.account, user: @contexto.user, turno_id: @contexto.turno_id,
                              status: Tarefa::AMOSTRA_PRONTA, descricao: @receita.descricao, receita: @receita.dados,
                              total: alvos.size, amostra: pares, custo_estimado: custo, teto_custo: custo * FOLGA_DO_TETO,
                              jev_estimado: @receita.usa_jev? ? alvos.size : 0, relatorio: jev_restante,
                              tempo_estimado: estimar_tempo(duracao, preparados.size, alvos.size))
      congelar(tarefa, alvos)
      tarefa
    end
  end

  def jev_restante
    @receita.usa_jev? ? { 'jev_restante' => ::Autonomia::Guide::Tarefas::Jev.restante(@contexto.account) } : {}
  end

  # A lista congelada: só referências, na ordem da leitura.
  def congelar(tarefa, alvos)
    agora = Time.current
    linhas = alvos.each_with_index.map do |alvo, indice|
      { task_id: tarefa.id, record_type: @receita.recurso, record_id: numero(alvo['id']), posicao: indice,
        status: ::Autonomia::Guide::TarefaItem::PENDENTE, created_at: agora, updated_at: agora }
    end
    ::Autonomia::Guide::TarefaItem.insert_all!(linhas) # rubocop:disable Rails/SkipsModelValidations
  end

  # O custo da IA do cliente na amostra, por item gerado, vezes o total. Sem `$gerar`, zero.
  def estimar_custo(preparados, total)
    gerados = preparados.count { |preparado| preparado.dados.present? }
    return 0 if @receita.gerar.empty? || gerados.zero?

    (@preparo.custo / gerados * total).round(6)
  end

  # O tempo da amostra por item (a leitura, o Jev e o `$gerar`), vezes o total, mais a espera entre lotes.
  def estimar_tempo(duracao, amostrados, total)
    lotes = (total / ::Autonomia::Guide::Tarefas::Lote::TAMANHO.to_f).ceil
    ((duracao / [amostrados, 1].max * total) + (lotes * ESPERA_ENTRE_LOTES)).ceil
  end

  def acoes
    @contexto.acoes
  end

  def vizinhas
    ::Autonomia::Guide::Rotas.vizinhas(acoes.catalogo, @receita.acao).join(', ').presence || 'nada parecido'
  end

  def numero(valor)
    Integer(valor.to_s, 10, exception: false)
  end

  def relogio
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
