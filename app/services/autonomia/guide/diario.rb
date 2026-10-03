# O caderno em que o Guia anota o que mudou no banco enquanto age (#855).
#
# O Guia executa pelos mesmos endpoints da tela, e cada endpoint grava do seu
# jeito. Por isso o "antes" não pode sair de uma lista de recursos escrita à
# mão: sai do próprio Rails. Toda linha que um model cria, altera ou apaga
# durante a ação passa pelos callbacks de `Autonomia::Guide::Anotavel`, e este
# caderno guarda o estado dela como o Postgres o tem (row_to_json). Assim o
# desfazer vale para as 487 ações do catálogo, inclusive as que ainda não
# existem.
#
# O caderno só existe dentro de `gravando`, na thread que executa a ação. Fora
# dele, os callbacks não fazem nada além de olhar uma variável da thread.
#
# O que ele NÃO enxerga, ele diz: apagar sem callback (`delete_all`,
# `dependent: :delete_all`, SQL direto) não passa pelo model, então não há
# "antes" para pôr de volta. Essas tabelas viram `pendencias` na execução, e a
# tela avisa que aquela parte não volta.
module Autonomia::Guide::Diario
  CHAVE = :autonomia_guide_diario

  # O próprio caderno e a trilha de auditoria não entram nele. Nem a conversa
  # com o Guia e o registro do pedido (#861): são do Guia, não dado da conta, e o
  # desfazer não pode apagá-los. Eles são gravados fora do caderno (`ChatJob`);
  # isto é a rede para quem um dia gravar lá dentro.
  FORA = %w[autonomia_guide_executions autonomia_guide_changes audits
            autonomia_guide_conversations autonomia_guide_turns].freeze

  APAGAR = 'DELETE'.freeze

  # Jobs que apagam ou alteram dado DEPOIS da requisição, fora do caderno. Se um
  # passo deixou um deles na fila, parte do que ele fez não volta com o desfazer.
  # As ações conhecidas por isso já pedem confirmação (`Acoes::SEM_DESFAZER`);
  # esta é a rede para o caso que ninguém previu.
  JOBS_QUE_APAGAM = %w[
    ActiveRecord::DestroyAssociationAsyncJob DeleteObjectJob Labels::RemoveAssociationsJob
    Companies::DeleteJob MacrosExecutionJob BulkActionsJob
  ].freeze
  EVENTOS_DE_JOB = %w[enqueue.active_job enqueue_at.active_job].freeze

  Entrada = Struct.new(:objeto, :tabela, :record_type, :record_id, :operacao, :antes, :depois, keyword_init: true)

  class Sessao
    attr_reader :entradas, :apagadas_por_sql

    def initialize
      @entradas = []
      @antes = {}.compare_by_identity
      @apagadas_por_sql = Hash.new(0)
      @jobs_que_apagam = []
    end

    def guardar_antes(objeto, linha)
      @antes[objeto] = linha
    end

    def antes_de(objeto)
      @antes.delete(objeto) || {}
    end

    def anotar(entrada)
      @entradas << entrada
    end

    def job_enfileirado(job)
      nome = job.class.name
      @jobs_que_apagam << nome if JOBS_QUE_APAGAM.include?(nome)
    end

    def sql_executado(sql)
      texto = sql.to_s.lstrip
      return unless texto[0, APAGAR.size].upcase == APAGAR

      tabela = texto.split[2].to_s.delete('"')
      @apagadas_por_sql[tabela] += 1 unless FORA.include?(tabela)
    end

    # Tabelas em que o banco apagou mais linhas do que os models anotaram.
    def pendencias
      anotadas = @entradas.select { |entrada| entrada.operacao == 'destroy' }.map(&:tabela).tally
      tabelas = @apagadas_por_sql.filter_map { |tabela, total| tabela if total > anotadas.fetch(tabela, 0) }
      tabelas + @jobs_que_apagam.uniq
    end
  end

  module_function

  def sessao
    Thread.current[CHAVE]
  end

  def ativo?
    sessao.present?
  end

  # Executa o bloco anotando tudo, e grava as mudanças como o passo `passo` da
  # execução. Devolve o que o bloco devolveu.
  def gravando(execucao, passo)
    raise ArgumentError, 'o caderno do Guia já está aberto nesta thread' if ativo?

    atual = Sessao.new
    Thread.current[CHAVE] = atual
    ouvintes = ouvir(atual)

    resultado = yield
    Thread.current[CHAVE] = nil
    persistir(execucao, passo, atual)
    resultado
  ensure
    Array(ouvintes).each { |ouvinte| ActiveSupport::Notifications.unsubscribe(ouvinte) }
    Thread.current[CHAVE] = nil
  end

  # O SQL e os jobs DESTA thread, durante a ação. As notificações são globais;
  # a conferência da sessão deixa de fora o que outras threads fazem ao mesmo tempo.
  def ouvir(atual)
    sql = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      atual.sql_executado(payload[:sql]) if Thread.current[CHAVE].equal?(atual)
    end
    jobs = EVENTOS_DE_JOB.map do |evento|
      ActiveSupport::Notifications.subscribe(evento) do |*, payload|
        atual.job_enfileirado(payload[:job]) if Thread.current[CHAVE].equal?(atual)
      end
    end
    [sql, *jobs]
  end

  # Só vira mudança o que de fato ficou no banco. Uma transação que voltou atrás
  # dentro do endpoint deixou anotação de algo que não aconteceu; a conferência
  # é feita aqui, na hora, quando ninguém mais mexeu naquelas linhas.
  def persistir(execucao, passo, atual)
    base = execucao.mudancas.maximum(:ordem).to_i
    linhas = conferidas(atual.entradas).each_with_index.map do |entrada, indice|
      { execution_id: execucao.id, passo: passo, ordem: base + indice + 1, tabela: entrada.tabela,
        record_type: entrada.record_type, record_id: entrada.record_id, operacao: entrada.operacao,
        antes: entrada.antes, depois: entrada.depois, created_at: Time.current, updated_at: Time.current }
    end
    # Em lote e sem callback: a mudança é registro do caderno, não dado da conta.
    ::Autonomia::Guide::Mudanca.insert_all!(linhas) if linhas.any? # rubocop:disable Rails/SkipsModelValidations
    execucao.anotar_pendencias(atual.pendencias)
  end

  # A linha como o Postgres a tem, ou só as colunas pedidas. Campo cifrado volta
  # cifrado: nada passa pelo tipo do Rails.
  def linha(objeto, colunas = nil)
    classe = objeto.class
    conexao = classe.connection
    sql = "SELECT row_to_json(t) FROM #{conexao.quote_table_name(classe.table_name)} t " \
          "WHERE #{conexao.quote_column_name(classe.primary_key)} = #{conexao.quote(objeto.id)}"
    dados = JSON.parse(conexao.select_value(sql) || '{}')
    colunas ? dados.slice(*colunas) : dados
  end

  def registravel?(objeto)
    ativo? && objeto.class.primary_key.is_a?(String) && FORA.exclude?(objeto.class.table_name)
  end

  def antes_de_alterar(objeto)
    sessao.guardar_antes(objeto, linha(objeto)) if registravel?(objeto)
  end

  def depois_de_alterar(objeto)
    return unless registravel?(objeto)

    antes = sessao.antes_de(objeto)
    colunas = objeto.saved_changes.keys
    return if colunas.empty?

    anotar(objeto, 'update', antes: antes.slice(*colunas), depois: linha(objeto, colunas))
  end

  def depois_de_criar(objeto)
    anotar(objeto, 'create', depois: linha(objeto)) if registravel?(objeto)
  end

  def antes_de_apagar(objeto)
    sessao.guardar_antes(objeto, linha(objeto)) if registravel?(objeto)
  end

  def depois_de_apagar(objeto)
    anotar(objeto, 'destroy', antes: sessao.antes_de(objeto)) if registravel?(objeto)
  end

  # A mesma linha alterada duas vezes: só a última alteração se compara com o
  # banco, as anteriores valem por ela.
  #
  # Linha que NASCEU neste passo não tem "antes" a restaurar: o que existia antes
  # do Guia era nada. Alterá-la ou apagá-la no mesmo passo não vira mudança — só
  # a criação conta, e só se a linha ainda existe. Sem isto, criar e apagar na
  # mesma requisição deixava só o "apagou", e o desfazer recriava uma linha que
  # nunca existiu (teste de produção, 03/10/2026).
  def conferidas(entradas)
    proprias = sem_o_que_nasceu_no_passo(entradas)
    ultima = ultima_alteracao(proprias)

    proprias.each_with_index.select do |entrada, indice|
      next true if entrada.operacao == 'update' && ultima[entrada.objeto] != indice

      ficou?(entrada)
    end.map(&:first)
  end

  def sem_o_que_nasceu_no_passo(entradas)
    nascidas = entradas.select { |entrada| entrada.operacao == 'create' }.to_set(&:objeto).compare_by_identity
    entradas.reject { |entrada| entrada.operacao != 'create' && nascidas.include?(entrada.objeto) }
  end

  def ultima_alteracao(entradas)
    ultima = {}.compare_by_identity
    entradas.each_with_index { |entrada, indice| ultima[entrada.objeto] = indice if entrada.operacao == 'update' }
    ultima
  end

  def ficou?(entrada)
    atual = linha(entrada.objeto)
    case entrada.operacao
    when 'create' then atual.present?
    when 'destroy' then atual.blank?
    else atual.slice(*entrada.depois.keys) == entrada.depois
    end
  end

  def anotar(objeto, operacao, antes: {}, depois: {})
    sessao.anotar(Entrada.new(objeto: objeto, tabela: objeto.class.table_name, record_type: objeto.class.name,
                              record_id: objeto.id, operacao: operacao, antes: antes, depois: depois))
  end
end
