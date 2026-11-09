# Como andar numa receita (#2414 F3): o primeiro passo, um passo pelo id e o que vem depois dele.
#
# Os ramos (`entao`, `senao`, `se_vencer` e os caminhos do "decidir") ficam dentro do passo que os abre, pela travessia
# única da Receita. Quando um ramo acaba, a receita segue no passo depois de quem o abriu, e assim por diante até o fim.
#
# O laço dos documentos (G46, exemplo 14): o caminho do "decidir" marcado no `de_novo` com `desde` não segue em frente
# quando acaba; volta ao "esperar até" `desde`, irmão anterior do "decidir" (DecidirDeNovo confere ao salvar). O caminho
# vazio volta direto. O ensaio (`voltar: false`) para no fim do caminho e diz para onde ele voltaria, em vez de rodar o
# laço de novo.
class Autonomia::Automacao::Roteiro
  def initialize(receita, voltar: true)
    @receita = receita
    @voltar = voltar
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
    return unless pai

    chave = chave_do_caminho(passo(pai), lista)
    chave ? fim_do_caminho(passo(pai), chave) : seguinte(pai)
  end

  # O primeiro passo de um ramo; se o ramo estiver vazio, o que vem depois de quem o abriu.
  def entrar(passo, ramo)
    Array(passo[ramo]).first || seguinte(passo['id'])
  end

  # O primeiro passo do caminho que o "decidir" escolheu (a chave, ou `nenhum`); caminho vazio, o fim dele.
  def entrar_no_caminho(passo, chave)
    caminho = Array(passo['caminhos']).find { |item| item['chave'] == chave }
    lista = caminho ? caminho['passos'] : passo[::Autonomia::Automacao::Receita::NENHUM]
    Array(lista).first || fim_do_caminho(passo, caminho ? chave : ::Autonomia::Automacao::Receita::NENHUM)
  end

  # Os passos antes de `id` na mesma lista, do mais perto ao mais longe.
  def anteriores(id)
    _passo, lista, indice = @lugares[id]
    lista ? lista.first(indice).reverse : []
  end

  # O passo para onde o caminho `chave` do "decidir" volta (G46), ou nil quando ele segue em frente.
  def volta(passo, chave)
    desde = passo.dig('de_novo', 'desde') if passo['tipo'] == 'decidir'
    desde if desde.present? && Array(passo.dig('de_novo', 'caminhos')).include?(chave)
  end

  private

  # Acabou o caminho `chave` do "decidir": volta ao `desde` (no ensaio, para) ou segue depois do "decidir".
  def fim_do_caminho(decidir, chave)
    desde = volta(decidir, chave)
    return seguinte(decidir['id']) unless desde

    passo(desde) if @voltar
  end

  # A chave do caminho do "decidir" cuja lista de passos é `lista` (a mesma lista da receita); nil fora do "decidir".
  def chave_do_caminho(pai, lista)
    return unless pai['tipo'] == 'decidir'
    return ::Autonomia::Automacao::Receita::NENHUM if pai[::Autonomia::Automacao::Receita::NENHUM].equal?(lista)

    Array(pai['caminhos']).find { |caminho| caminho['passos'].equal?(lista) }&.fetch('chave', nil)
  end

  def mapear(lista, pai)
    Array(lista).each_with_index do |passo, indice|
      @lugares[passo['id']] = [passo, lista, indice, pai]
      ::Autonomia::Automacao::Receita.ramos(passo).each { |ramo| mapear(ramo, passo['id']) }
    end
  end
end
