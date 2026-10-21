# O código anterior aguenta o schema novo? (#2024)
#
# A migration roda na green antes da troca de tráfego, com a blue servindo, e a blue é o alvo do rollback rápido.
# Então o código da versão anterior tem de funcionar no schema que as migrations deixam. A blue guarda as colunas de
# cada tabela desde que subiu e as manda em todo INSERT, então quebra quando some uma coluna (remoção ou renomeação),
# quando o tipo muda e quando uma coluna que ela grava como nula passa a ser NOT NULL. Coluna nova NOT NULL sem default
# numa tabela que já existe também quebra: a blue não a conhece e o INSERT dela vai sem o valor.
#
# Remover de propósito segue o expand/contract: primeiro um PR com `ignored_columns` no model e a coluna (ou tabela)
# em db/retiradas.yml; depois que ele está no ar, outro PR com a remoção. O arquivo vale como estava na base do lote,
# então a remoção nunca passa no mesmo lote que a anuncia.
class MigrationsSeguras::Compatibilidade
  Achado = Struct.new(:onde, :motivo, keyword_init: true) do
    def to_s
      "`#{onde}`: #{motivo}"
    end
  end

  attr_reader :bloqueios, :avisos

  def initialize(antes:, depois:, retiradas: {})
    @antes = antes
    @depois = depois
    @colunas_retiradas = Array(retiradas['colunas']).map(&:to_s)
    @tabelas_retiradas = Array(retiradas['tabelas']).map(&:to_s)
    @bloqueios = []
    @avisos = []
    verificar
  end

  def compativel?
    bloqueios.empty?
  end

  private

  def verificar
    @antes.fetch('tabelas').each do |nome, tabela|
      nova = @depois.fetch('tabelas')[nome]
      next tabela_removida(nome) unless nova

      comparar_colunas(nome, tabela.fetch('colunas'), nova.fetch('colunas'))
      comparar_regras(nome, tabela, nova)
    end
    comparar_objetos
  end

  def tabela_removida(nome)
    return if @tabelas_retiradas.include?(nome)

    bloquear(nome, 'tabela removida ou renomeada; o código anterior ainda a usa (expand/contract: db/retiradas.yml)')
  end

  def comparar_colunas(tabela, antes, depois)
    antes.each do |coluna, retrato|
      onde = "#{tabela}.#{coluna}"
      novo = depois[coluna]
      next coluna_removida(onde) unless novo

      bloquear(onde, "tipo mudou de #{retrato['tipo']} para #{novo['tipo']}") if novo['tipo'] != retrato['tipo']
      bloquear(onde, 'passou a ser NOT NULL; o código anterior grava nulo nela') if retrato['nulo'] && !novo['nulo']
    end
    (depois.keys - antes.keys).each { |coluna| coluna_nova(tabela, coluna, depois[coluna]) }
  end

  def coluna_removida(onde)
    return if @colunas_retiradas.include?(onde)

    bloquear(onde, 'coluna removida ou renomeada; o código anterior ainda a grava (expand/contract: ignored_columns e db/retiradas.yml)')
  end

  def coluna_nova(tabela, coluna, retrato)
    return if retrato['nulo'] || retrato['default'] || retrato['default_funcao']

    bloquear("#{tabela}.#{coluna}", 'coluna nova NOT NULL sem default numa tabela que já existe; o INSERT do código anterior vai sem ela')
  end

  # Índice único, chave estrangeira e restrição novos numa tabela que já existe podem recusar uma escrita que o código
  # anterior faz. Não bloqueia (quase sempre é a regra que se quer), mas sai no relatório para a revisão olhar.
  def comparar_regras(tabela, antes, depois)
    novos_unicos = depois.fetch('indices').select { |nome, indice| indice['unico'] && !antes.fetch('indices').key?(nome) }
    novos_unicos.each_key { |nome| avisar("#{tabela}.#{nome}", 'índice único novo em tabela que já existe') }
    avisar_novos(tabela, antes, depois, 'chaves_estrangeiras', 'chave estrangeira nova em tabela que já existe')
    avisar_novos(tabela, antes, depois, 'restricoes', 'restrição (CHECK) nova em tabela que já existe')
    avisar_novos(tabela, depois, antes, 'indices', 'índice removido; consulta do código anterior pode ficar lenta')
  end

  # Avisa o que existe em `depois` e não em `antes` (com os dois trocados, o que sumiu).
  def avisar_novos(tabela, antes, depois, chave, motivo)
    (depois.fetch(chave).keys - antes.fetch(chave).keys).each { |nome| avisar("#{tabela}.#{nome}", motivo) }
  end

  def comparar_objetos
    { 'views' => 'view', 'extensoes' => 'extensão', 'tipos_enum' => 'tipo enum' }.each do |chave, rotulo|
      (lista(@antes[chave]) - lista(@depois[chave])).each { |nome| bloquear(nome, "#{rotulo} removida") }
    end
    { 'funcoes' => 'função', 'gatilhos' => 'gatilho' }.each do |chave, rotulo|
      (lista(@antes[chave]) - lista(@depois[chave])).each { |nome| avisar(nome, "#{rotulo} removida") }
    end
    comparar_valores_de_enum
  end

  # Valor que some de um tipo enum quebra a linha que o código anterior grava com ele.
  def comparar_valores_de_enum
    @antes.fetch('tipos_enum', {}).each do |nome, valores|
      removidos = valores - @depois.fetch('tipos_enum', {}).fetch(nome, valores)
      removidos.each { |valor| bloquear("#{nome}.#{valor}", 'valor removido do tipo enum') }
    end
  end

  def lista(valor)
    valor.is_a?(Hash) ? valor.keys : Array(valor)
  end

  def bloquear(onde, motivo)
    @bloqueios << Achado.new(onde: onde, motivo: motivo)
  end

  def avisar(onde, motivo)
    @avisos << Achado.new(onde: onde, motivo: motivo)
  end
end
