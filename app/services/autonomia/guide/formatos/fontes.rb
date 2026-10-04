# O código-fonte dos controllers, lido com o Prism (#900).
#
# Cada arquivo é analisado uma vez por geração: o mesmo controller atende
# várias ações, e o mesmo concern aparece em vários controllers.
module Autonomia::Guide::Formatos::Fontes
  PASTAS = %w[app/controllers/ enterprise/app/controllers/ custom/app/controllers/].freeze

  module_function

  # O `def` de um método (UnboundMethod), ou nil se ele não mora nos
  # controllers do repositório — gem, helper ou modelo não são lidos: o que
  # eles fazem com `params` não é o formato da ação (e é ali que o leitor
  # anterior pegava ruído, como as validações de IMAP do helper de caixas).
  def definicao(metodo)
    arquivo, linha = metodo.source_location
    return unless arquivo && do_controller?(arquivo)

    definicoes(arquivo)[[linha, metodo.name]]
  end

  # Método que mora fora do repositório (gem) e lê `params` no próprio corpo (#942). Só o corpo do
  # método: o que ele chama adiante não é seguido.
  def de_fora_le_params?(metodo, caminhos)
    arquivo, linha = metodo.source_location
    return false if arquivo.nil? || !File.file?(arquivo) || do_repositorio?(arquivo)

    pilha = [definicoes(arquivo)[[linha, metodo.name]]&.body].compact
    until pilha.empty?
      node = pilha.pop
      return true if caminhos.params?(node)

      pilha.concat(node.compact_child_nodes)
    end
    false
  end

  def do_controller?(arquivo)
    do_repositorio?(arquivo) && PASTAS.any? { |pasta| relativo(arquivo).start_with?(pasta) }
  end

  # Código nosso: dentro do Rails.root e fora de onde o Bundler instala gems. No CI
  # as gems ficam em `vendor/bundle`, DENTRO do Rails.root; só o prefixo fazia o
  # `create` do ActiveStorage parecer nosso e o formato saía diferente do Mac.
  def do_repositorio?(arquivo)
    caminho = File.expand_path(arquivo.to_s)
    caminho.start_with?(Rails.root.to_s + File::SEPARATOR) && pastas_de_gems.none? { |pasta| caminho.start_with?(pasta) }
  end

  def pastas_de_gems
    [Bundler.bundle_path.to_s, *Gem.path].map { |pasta| File.expand_path(pasta) + File::SEPARATOR }.uniq
  end

  def relativo(arquivo)
    arquivo.to_s.delete_prefix(Rails.root.to_s + File::SEPARATOR)
  end

  def origem(arquivo, node)
    "#{relativo(arquivo)}:#{node.location.start_line}"
  end

  def definicoes(arquivo)
    @definicoes ||= {}
    @definicoes[arquivo] ||= indexar(Prism.parse_file(arquivo).value)
  end

  def indexar(raiz)
    pilha = [raiz]
    indice = {}
    until pilha.empty?
      node = pilha.pop
      indice[[node.location.start_line, node.name]] = node if node.is_a?(Prism::DefNode)
      pilha.concat(node.compact_child_nodes)
    end
    indice
  end
end
