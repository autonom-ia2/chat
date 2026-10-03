# Os `permit` de uma action, resolvidos (#900): cada um como
# `[caminho, árvore, envelope?]`.
#
# O que a leitura do código diz entra direto. Onde ela não diz — splat de
# método, valor calculado — ou onde o método consulta recurso da conta, o
# `Espiao` executa o montador de parâmetros com a conta sem recurso e com
# todos, e o resultado se junta ao lido. Daí saem também o `so_se` (campo que
# só existe com recurso ligado) e o canal por tipo.
class Autonomia::Guide::Formatos::Resolucao
  Formatos = ::Autonomia::Guide::Formatos
  Filtros = Formatos::Filtros

  attr_reader :motivos, :por_tipo, :so_se

  def initialize(klass, coleta, nao_executar:)
    @klass = klass
    @coleta = coleta
    @nao_executar = nao_executar
    @espiao = Formatos::Espiao.new(klass)
    @motivos = []
    @por_tipo = {}
    @so_se = {}
  end

  def permits
    @permits ||= @coleta.permits.group_by { |permit| [permit.dono, permit.metodo] }.flat_map do |(_dono, metodo), lista|
      recortar(metodo, resolver(metodo, lista))
    end
  end

  private

  # O update da conta usa `account_params.slice(:name, :locale, ...)`, e o
  # `account_params` é o do cadastro (aceita `account_name`, `password`...). O
  # que o slice deixa de fora é descartado calado, então não entra no formato.
  # Recorte com chave calculada não se resolve: o formato fica parcial.
  def recortar(metodo, permits)
    chaves = @coleta.recorte_de(metodo)
    return permits unless chaves
    return permits.tap { @motivos << "o permit de #{metodo} é recortado por valor calculado" } if chaves.any?(Filtros::Dinamico)

    nomes = chaves.map(&:to_s)
    permits.map { |caminho, arvore, envelope| [caminho, arvore.slice(*nomes), envelope] }
  end

  def resolver(metodo, lista)
    estaticos = lista.map { |permit| [permit.caminho, Filtros.arvore(permit.filtros), permit.envelope] }
    dinamico = estaticos.map(&:second).any? { |arvore| Filtros.dinamica?(arvore) }
    executados = executar(metodo, lista) if dinamico || @coleta.recursos.any?
    executados ? executados + estaticos : nao_resolvido(estaticos, dinamico)
  end

  def nao_resolvido(estaticos, dinamico)
    @motivos << 'permit com valor calculado que não deu para resolver' if dinamico
    estaticos
  end

  def executar(metodo, lista)
    return if @nao_executar.include?(metodo.to_s)

    com = @espiao.permits(metodo, conta: Formatos::Espiao.conta_com_recursos)
    sem = @espiao.permits(metodo, conta: Formatos::Espiao.conta_sem_recursos)
    return if com.blank? || sem.nil?

    marcar_so_se(com, sem)
    com.map do |caminho, filtros|
      arvore = Filtros.arvore(filtros)
      canais(metodo, arvore)
      [caminho, arvore, lista.any?(&:envelope) && caminho.size == 1]
    end
  end

  def canais(metodo, arvore)
    return unless Formatos::Canais.aplica?(@klass, metodo, arvore)

    @por_tipo = Formatos::Canais.por_tipo(@espiao, metodo, Formatos::Espiao.conta_com_recursos)
  end

  # O campo que só aparece com todos os recursos ligados depende da conta. A
  # chave é o caminho dentro do envelope (`config.auto_resolve_after`).
  def marcar_so_se(com, sem)
    sem_recurso = sem.map(&:last).flat_map { |filtros| nomes(Filtros.arvore(filtros)) }
    recursos = @coleta.recursos.uniq.sort.join(', ').presence || 'recurso da conta'
    com.map(&:last).each do |filtros|
      (nomes(Filtros.arvore(filtros)) - sem_recurso).each { |campo| @so_se[campo] = "só com #{recursos} ligado na conta" }
    end
  end

  def nomes(arvore, prefixo = nil)
    arvore.flat_map do |nome, campo|
      next [] if nome.is_a?(Filtros::Dinamico)

      caminho = [prefixo, nome].compact.join('.')
      [caminho, *nomes(campo[:campos] || {}, caminho)]
    end
  end
end
