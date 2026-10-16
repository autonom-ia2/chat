# A MARCA dos envios em nome de pessoa (#1669): a segunda metade da VarreduraDeEnviosEmNomeDePessoa, separada para
# cada arquivo ler como uma coisa só. Aqui se decide se um envio achado tem a marca de envio automático como chave do
# valor de content_attributes/additional_attributes, seguindo variável local e método do mesmo dono.
module VarreduraDeEnviosEmNomeDePessoa
  module_function

  # { [dono, nome] => DefNode } da árvore: o mesmo nome em classes diferentes não se mistura.
  def metodos(arvore)
    defs = {}
    cada_no(arvore) { |nodo, dono, _metodo| defs[[dono, nodo.name]] = nodo if nodo.is_a?(Prism::DefNode) }
    defs
  end

  def def_do(arvore, envio)
    metodos(arvore)[[envio.dono, envio.metodo]]
  end

  # A marca está como chave do valor de content_attributes/additional_attributes do envio?
  def marcado?(envio, arvore)
    contexto = { defs: metodos(arvore), dono: envio.dono, corpo: def_do(arvore, envio), vistos: Set.new }
    chaves_dos_atributos(envio.chamada, contexto).intersect?(marcas)
  end

  # Procura `content_attributes:`/`additional_attributes:` dentro do nó (seguindo variável local e método do dono) e
  # devolve as chaves do valor deles.
  def chaves_dos_atributos(nodo, contexto)
    achadas = []
    cada_no(nodo) do |filho, _dono, _metodo|
      achadas.concat(chaves_do_valor(filho.value, contexto)) if CHAVES_DE_ATRIBUTOS.include?(chave(filho))
      achadas.concat(seguir(filho, contexto) { |alvo| chaves_dos_atributos(alvo, contexto) })
    end
    achadas
  end

  # As chaves de primeiro nível de um valor de atributos: hash literal, `x.merge(...)`, variável local ou método.
  def chaves_do_valor(valor, contexto)
    case valor
    when Prism::HashNode, Prism::KeywordHashNode then valor.elements.filter_map { |elemento| chave(elemento) }
    when Prism::CallNode
      if valor.receiver
        chaves_do_valor(valor.receiver, contexto) + argumentos(valor).flat_map { |arg| chaves_do_valor(arg, contexto) }
      else
        seguir(valor, contexto) { |alvo| chaves_de_retorno(alvo, contexto) }
      end
    when Prism::LocalVariableReadNode then seguir(valor, contexto) { |alvo| chaves_do_valor(alvo, contexto) }
    else []
    end
  end

  # As chaves de hash que um método devolve: a última expressão do corpo, seguindo as atribuições locais.
  def chaves_de_retorno(corpo, contexto)
    ultima = corpo.body&.body&.last
    return [] if ultima.nil?

    chaves_do_valor(ultima, contexto.merge(corpo: corpo))
  end

  # Segue uma leitura de variável local (para o valor atribuído no método do envio) ou uma chamada sem receptor e sem
  # argumento (para o método do mesmo dono). Cada alvo uma vez só.
  def seguir(nodo, contexto, &)
    alvos = alvos_de(nodo, contexto).reject { |alvo| contexto[:vistos].include?(alvo.object_id) }
    alvos.each { |alvo| contexto[:vistos] << alvo.object_id }
    alvos.flat_map(&)
  end

  def alvos_de(nodo, contexto)
    case nodo
    when Prism::LocalVariableReadNode
      escritas_em(contexto[:corpo]).select { |escrita| escrita.name == nodo.name }.map(&:value)
    when Prism::CallNode
      return [] unless nodo.receiver.nil? && argumentos(nodo).empty?

      [contexto[:defs][[contexto[:dono], nodo.name]]].compact
    else []
    end
  end

  def escritas_em(corpo)
    return [] if corpo.nil?

    escritas = []
    cada_no(corpo) { |nodo, _dono, _metodo| escritas << nodo if nodo.is_a?(Prism::LocalVariableWriteNode) }
    escritas
  end

  def sem_marca(revisados)
    arquivos.flat_map do |arquivo|
      arvore = arvore_de(arquivo)
      envios_em(arvore, arquivo).reject do |envio|
        revisados.key?(envio.id) || (envio.tipo == :com_remetente && marcado?(envio, arvore))
      end
    end
  end
end
