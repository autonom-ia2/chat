# Kit de demo (#2140): lê do db/seeds.rb a senha do usuário do seed, para o login dos prints.
# Assim o kit não guarda senha nenhuma. Usa o parser do próprio Ruby (Prism), sem Rails.
# Uso: ruby senha_do_seed.rb <db/seeds.rb> <email>
require 'prism'

arquivo, email = ARGV
abort 'uso: ruby senha_do_seed.rb <db/seeds.rb> <email>' unless arquivo && email

resultado = Prism.parse_file(arquivo)
abort "não consegui ler #{arquivo}" unless resultado.success?

def texto(node)
  node.unescaped if node.is_a?(Prism::StringNode) || node.is_a?(Prism::SymbolNode)
end

# { chave => valor } de um hash literal ou dos argumentos nomeados (email: ..., password: ...).
def pares(node)
  return {} unless node.is_a?(Prism::KeywordHashNode) || node.is_a?(Prism::HashNode)

  node.elements.grep(Prism::AssocNode).to_h { |par| [texto(par.key), texto(par.value)] }
end

def senha_em(node, email)
  campos = pares(node)
  return campos['password'] if campos['email'] == email && campos['password']

  node.compact_child_nodes.each do |filho|
    achada = senha_em(filho, email)
    return achada if achada
  end
  nil
end

senha = senha_em(resultado.value, email)
abort "não achei a senha de #{email} em #{arquivo}" unless senha

print senha
