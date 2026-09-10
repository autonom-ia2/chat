require 'prism'

# VARREDURA DAS SAÍDAS DE RECUSA (entrega 6), compartilhada entre a guarda (`recusa_guarda_spec`)
# e os exemplos (`recusa_registro_spec`). É ela que decide o que existe; os specs só perguntam.
#
# Por AST (Prism), não por texto: busca textual de `error:` acusa comentário e string, e não acha o
# que importa — um Hash com a chave `error` sendo montado fora do produtor único.
module VarreduraDeRecusas
  # Tudo que é do agente: ferramentas, principal, especialistas, jobs. Recursivo, para que um
  # arquivo novo entre sozinho na varredura.
  RAIZES = %w[app/services/autonomia/agents app/jobs/autonomia/agents].freeze
  # Onde um `{ error: ... }` montado à mão já é suspeito mesmo sem `.to_json` colado.
  RAIZES_DE_FERRAMENTA = %w[
    app/services/autonomia/agents/tools
    app/services/autonomia/agents/specialists
    app/services/autonomia/agents/answerer.rb
    app/jobs/autonomia/agents/tools
  ].freeze
  PRODUTOR_UNICO = 'app/services/autonomia/agents/tools/recusa.rb'.freeze
  BOUND = 'app/services/autonomia/agents/tools/bound.rb'.freeze
  # Chamadas cujo PRIMEIRO argumento é o código da recusa: sem receptor (o atalho da própria classe),
  # sobre `self`, ou sobre a constante `Recusa`. `error` é o atalho de `Native::Base`;
  # `Rails.logger.error` tem outro receptor e fica fora. Um apelido local (`r = Recusa; r.para_modelo`)
  # esconderia a saída da varredura — por isso os chamadores usam a constante por extenso.
  REGISTRADORES = %i[recusar registrar para_modelo recusa conferencia error].freeze

  # Uma SAÍDA: uma chamada ao registrador, ou um `return 'codigo'` no Bound. O id é estável
  # enquanto o método não mudar de nome: `bound.rb#accept_async#2`.
  Saida = Struct.new(:arquivo, :linha, :metodo, :ordem, :codigo) do
    def id
      "#{File.basename(arquivo)}##{metodo}##{ordem}"
    end

    def to_s
      "#{arquivo}:#{linha}  #{id}  #{codigo || '(código dinâmico)'}"
    end
  end

  module_function

  def arquivos
    RAIZES.flat_map { |raiz| Dir[Rails.root.join(raiz, '**', '*.rb').to_s] }
          .map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.sort
  end

  def de_ferramenta?(caminho)
    RAIZES_DE_FERRAMENTA.any? { |raiz| caminho == raiz || caminho.start_with?("#{raiz}/") }
  end

  def arvore(caminho)
    Prism.parse_file(Rails.root.join(caminho).to_s).value
  end

  # Percorre a árvore inteira entregando cada nó e o nome do método que o contém.
  def cada_no(nodo, metodo = nil, &)
    return if nodo.nil?

    metodo = nodo.name if nodo.is_a?(Prism::DefNode)
    yield(nodo, metodo)
    nodo.compact_child_nodes.each { |filho| cada_no(filho, metodo, &) }
  end

  # As formas de montar `{"error":...}` para o modelo. Nas pastas de ferramenta: qualquer hash
  # literal com `error`, `h['error'] = x` e `Hash[...]` com `error`. Nos demais arquivos do agente:
  # só o hash com `error` que vira JSON — um hash com essa chave solto ali é estrutura interna
  # (`AnswerResult`), não saída de ferramenta. Argumento nomeado de método (`Result.new(error: ...)`)
  # fica de fora pelo mesmo motivo. -> ["arquivo:linha  trecho", ...]
  def produtores_de_erro(caminho)
    de_ferramenta = de_ferramenta?(caminho)
    achados = []
    cada_no(arvore(caminho)) do |nodo, _metodo|
      suspeito = de_ferramenta ? Nos.produtor_em_ferramenta?(nodo) : Nos.vira_json_com_error?(nodo)
      achados << "#{caminho}:#{nodo.location.start_line}  #{nodo.slice.lines.first.strip}" if suspeito
    end
    achados
  end

  # Todas as saídas de recusa, fora do produtor único.
  def saidas
    arquivos.reject { |caminho| caminho == PRODUTOR_UNICO }.flat_map { |caminho| saidas_em(caminho) }
  end

  # Um método que se chama como registrador (`Bound#recusar`, `Runner#recusar`) é ATALHO, não saída:
  # as saídas são os lugares que o chamam. Sem isto cada atalho contaria duas vezes.
  def saidas_em(caminho)
    raiz = arvore(caminho)
    constantes = Nos.constantes_de_texto(raiz)
    ordem = Hash.new(0)
    lista = []
    cada_no(raiz) do |nodo, metodo|
      next if REGISTRADORES.include?(metodo) || !saida?(nodo, caminho, constantes)

      ordem[metodo] += 1
      lista << Saida.new(caminho, nodo.location.start_line, metodo, ordem[metodo], Nos.primeiro_literal(nodo, constantes))
    end
    lista
  end

  def saida?(nodo, caminho, constantes)
    return true if Nos.registrador?(nodo)
    return false unless caminho == BOUND && nodo.is_a?(Prism::ReturnNode)

    Nos.primeiro_literal(nodo, constantes)&.match?(::Autonomia::Agents::Tools::Recusa::CODIGO) || false
  end
end

# Os predicados sobre nós do Prism, separados para a varredura ler como prosa.
module VarreduraDeRecusas::Nos
  module_function

  # `error:` e `'error' =>` são a mesma chave depois do `to_json`.
  def error?(nodo)
    (nodo.is_a?(Prism::SymbolNode) || nodo.is_a?(Prism::StringNode)) && nodo.unescaped == 'error'
  end

  def hash_com_error?(nodo)
    (nodo.is_a?(Prism::HashNode) || nodo.is_a?(Prism::KeywordHashNode)) &&
      nodo.elements.any? { |elemento| elemento.is_a?(Prism::AssocNode) && error?(elemento.key) }
  end

  def argumentos(nodo)
    nodo.respond_to?(:arguments) ? Array(nodo.arguments&.arguments) : []
  end

  def chamada?(nodo, nome)
    nodo.is_a?(Prism::CallNode) && nodo.name == nome
  end

  # `JSON`, `::JSON` ou `Tools::Recusa`: o último segmento do nome.
  def sobre_constante?(nodo, nome)
    (nodo.receiver.is_a?(Prism::ConstantReadNode) || nodo.receiver.is_a?(Prism::ConstantPathNode)) && nodo.receiver.name == nome
  end

  # Com argumento: `error` sem argumento é o leitor de atributo de `AnswerResult`, não o atalho.
  def registrador?(nodo)
    return false unless nodo.is_a?(Prism::CallNode) && VarreduraDeRecusas::REGISTRADORES.include?(nodo.name)
    return false if argumentos(nodo).empty?

    nodo.receiver.nil? || nodo.receiver.is_a?(Prism::SelfNode) || sobre_constante?(nodo, :Recusa)
  end

  # `{ error: x }.to_json`, `JSON.generate(error: x)` ou `JSON.dump(error: x)` — as formas que vão
  # ao modelo. `generate`/`dump` recebem o hash como argumento nomeado (`KeywordHashNode`).
  def vira_json_com_error?(nodo)
    to_json_de_hash_com_error?(nodo) || gera_json_com_error?(nodo)
  end

  def to_json_de_hash_com_error?(nodo)
    chamada?(nodo, :to_json) && nodo.receiver.is_a?(Prism::HashNode) && hash_com_error?(nodo.receiver)
  end

  def gera_json_com_error?(nodo)
    (chamada?(nodo, :generate) || chamada?(nodo, :dump)) && sobre_constante?(nodo, :JSON) &&
      argumentos(nodo).any? { |arg| hash_com_error?(arg) }
  end

  # `h['error'] = x`, `h.store(:error, x)`
  def atribui_error?(nodo)
    (chamada?(nodo, :[]=) || chamada?(nodo, :store)) && error?(argumentos(nodo).first)
  end

  # `{}.merge(error: x)`, `h.merge!(error: x)`, `h.update(error: x)`
  def mescla_error?(nodo)
    %i[merge merge! update].any? { |nome| chamada?(nodo, nome) } && argumentos(nodo).any? { |arg| hash_com_error?(arg) }
  end

  # `Hash[error: x]` ou `Hash[:error, x]`
  def constroi_hash_com_error?(nodo)
    chamada?(nodo, :[]) && sobre_constante?(nodo, :Hash) && argumentos(nodo).any? { |arg| error?(arg) || hash_com_error?(arg) }
  end

  # O hash literal já conta por si; `.to_json` colado nele não conta de novo.
  def produtor_em_ferramenta?(nodo)
    (nodo.is_a?(Prism::HashNode) && hash_com_error?(nodo)) || gera_json_com_error?(nodo) ||
      atribui_error?(nodo) || constroi_hash_com_error?(nodo) || mescla_error?(nodo)
  end

  # O literal que o PRIMEIRO argumento carrega, mesmo escondido: `'x'`, `CONSTANTE` definida no
  # mesmo arquivo como texto, ou `algo || 'x'` (o lado direito é o padrão). Dinâmico -> nil.
  def primeiro_literal(nodo, constantes)
    literal_de(argumentos(nodo).first, constantes)
  end

  def literal_de(nodo, constantes)
    case nodo
    when Prism::StringNode then nodo.unescaped
    when Prism::ConstantReadNode then constantes[nodo.name]
    when Prism::OrNode then literal_de(nodo.right, constantes) || literal_de(nodo.left, constantes)
    end
  end

  # `NOME = 'texto'.freeze` no arquivo -> { NOME: 'texto' }
  def constantes_de_texto(raiz)
    constantes = {}
    VarreduraDeRecusas.cada_no(raiz) do |nodo, _metodo|
      next unless nodo.is_a?(Prism::ConstantWriteNode)

      valor = nodo.value
      valor = valor.receiver if valor.is_a?(Prism::CallNode) && valor.name == :freeze
      constantes[nodo.name] = valor.unescaped if valor.is_a?(Prism::StringNode)
    end
    constantes
  end
end
