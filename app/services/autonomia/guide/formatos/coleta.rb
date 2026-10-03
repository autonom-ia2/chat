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
# - `origens`: onde a leitura achou algo, para quem revisa conferir.
class Autonomia::Guide::Formatos::Coleta
  Permit = Struct.new(:caminho, :filtros, :metodo, :dono, :origem, :envelope, keyword_init: true)
  Leitura = Struct.new(:caminho, :origem, :exigida, keyword_init: true)
  Candidato = Struct.new(:modelo, :da_action, keyword_init: true)

  attr_reader :permits, :leituras, :livres, :totais, :repasses, :corpo_cru, :externos, :modelos, :recursos,
              :envelopes_flexiveis

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
  end

  def origens
    (permits.map(&:origem) + leituras.map(&:origem) + livres.map(&:origem) + totais + corpo_cru).uniq
  end
end
