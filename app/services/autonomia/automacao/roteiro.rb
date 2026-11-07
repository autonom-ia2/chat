# Como andar numa receita (#2414 F3): o primeiro passo, um passo pelo id e o que vem depois dele.
#
# Os ramos (`entao`, `senao`, `se_vencer` e os caminhos do "decidir") ficam dentro do passo que os abre, pela travessia
# única da Receita. Quando um ramo acaba, a receita segue no passo depois de quem o abriu, e assim por diante até o fim.
class Autonomia::Automacao::Roteiro
  # A filha do "em outro registro" (G18, #2671) anda só no ramo do passo que a abriu: começa no primeiro passo dele e
  # acaba no fim dele, sem seguir os passos da mãe. As outras execuções andam na receita inteira.
  def self.da(execucao)
    receita = execucao.versao.receita
    _mae_id, passo_id = ::Autonomia::Automacao::EmOutroRegistro.da(execucao)
    passo = passo_id && new(receita).passo(passo_id)
    passo ? new('passos' => Array(passo['passos'])) : new(receita)
  end

  def initialize(receita)
    @receita = receita
    @lugares = {}
    mapear(receita['passos'], nil)
  end

  def primeiro
    @receita['passos'].first
  end

  def passo(id)
    @lugares[id]&.first
  end

  # O passo depois de `id`, saindo dos ramos que acabaram. nil = fim da receita.
  def seguinte(id)
    _passo, lista, indice, pai = @lugares.fetch(id)
    return lista[indice + 1] if indice + 1 < lista.size

    pai && seguinte(pai)
  end

  # O primeiro passo de um ramo; se o ramo estiver vazio, o que vem depois de quem o abriu.
  def entrar(passo, ramo)
    Array(passo[ramo]).first || seguinte(passo['id'])
  end

  # O primeiro passo do caminho que o "decidir" escolheu (a chave, ou `nenhum`); caminho vazio, o que vem depois.
  def entrar_no_caminho(passo, chave)
    caminho = Array(passo['caminhos']).find { |item| item['chave'] == chave }
    return entrar(passo, ::Autonomia::Automacao::Receita::NENHUM) unless caminho

    Array(caminho['passos']).first || seguinte(passo['id'])
  end

  private

  def mapear(lista, pai)
    Array(lista).each_with_index do |passo, indice|
      @lugares[passo['id']] = [passo, lista, indice, pai]
      ::Autonomia::Automacao::Receita.ramos(passo).each { |ramo| mapear(ramo, passo['id']) }
    end
  end
end
