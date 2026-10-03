# O que a leitura do código de uma action achou (#900). Só acumula; quem dá
# sentido é o `Gerador`.
#
# - `permits`: cada `permit`, com o caminho de onde ele lê (`[]` é a raiz,
#   `['custom_role']` é o que veio de `require(:custom_role)`), os filtros e o
#   método onde está — é esse método que o `Espiao` executa quando os filtros
#   não saem do código.
# - `leituras`: `params[:x]`, `dig`, `fetch`, `require` sem `permit`.
# - `livres`: `permit!` num campo de dentro (aceita objeto com qualquer chave).
# - `totais`: `permit!` na raiz ou no envelope — aceita qualquer coisa.
# - `repasses`: `params` inteiro entregue a outro objeto, que decide o resto.
# - `corpo_cru`: leitura de `request.body`.
# - `externos`: a action termina, por `super`, em código de gem.
# - `modelos`: `Current.account.<assoc>` e constante de modelo citada; a da
#   própria action vale mais que a de um `before_action`.
# - `recursos`: `feature_enabled?('x')` — o campo pode depender da conta.
# - `envelopes_flexiveis`: envelope lido por um método que também aceita o
#   corpo plano (`parameter_set` do CRM).
# - `recortes`: `account_params.slice(:name, ...)` — o que a action usa de um
#   montador de parâmetros que aceita mais (o `account_params` é do cadastro).
# - `chamadas`: cada chamada a método do próprio controller, pelo lugar no
#   código; o recorte só vale quando TODA chamada ao montador é recortada.
# - `destinos`: onde o corpo é gravado (`Destinos`), e `variaveis`, o modelo
#   de cada `@x` que um `before_action` busca.
# - `origens`: onde a leitura achou algo, para quem revisa conferir.
class Autonomia::Guide::Formatos::Coleta
  Permit = Struct.new(:caminho, :filtros, :metodo, :dono, :origem, :envelope, keyword_init: true)
  Leitura = Struct.new(:caminho, :origem, :exigida, keyword_init: true)
  Candidato = Struct.new(:modelo, :da_action, keyword_init: true)
  Recorte = Struct.new(:metodo, :chaves, :lugar, keyword_init: true)
  Destino = Struct.new(:modelo, :variavel, :metodo, keyword_init: true)

  attr_reader :permits, :leituras, :livres, :totais, :repasses, :corpo_cru, :externos, :modelos, :recursos,
              :envelopes_flexiveis, :recortes, :chamadas, :destinos, :variaveis

  def initialize
    @permits = []
    @leituras = []
    @livres = []
    @totais = []
    @repasses = []
    @corpo_cru = []
    @externos = []
    @modelos = []
    @recursos = []
    @envelopes_flexiveis = []
    @recortes = []
    @chamadas = []
    @destinos = []
    @variaveis = {}
  end

  # As chaves que a action usa do montador `metodo`, ou nil quando alguma
  # chamada a ele usa o resultado inteiro.
  def recorte_de(metodo)
    seus = recortes.select { |recorte| recorte.metodo == metodo }
    return if seus.empty? || chamadas_a(metodo) != seus.map(&:lugar).sort

    seus.flat_map(&:chaves)
  end

  def chamadas_a(metodo)
    chamadas.select { |nome, _lugar| nome == metodo }.map(&:last).sort
  end

  # O modelo que recebe o corpo, quando a action grava um `permit` num modelo
  # que se sabe qual é. Nil quando o corpo vai para serviço ou cliente externo.
  def destino
    montadores = permits.map(&:metodo)
    destinos.each do |destino|
      next unless destino.metodo == :permit || montadores.include?(destino.metodo)

      modelo = destino.modelo || variaveis[destino.variavel]
      return modelo if modelo
    end
    nil
  end

  def origens
    (permits.map(&:origem) + leituras.map(&:origem) + livres.map(&:origem) + totais + corpo_cru).uniq
  end
end
