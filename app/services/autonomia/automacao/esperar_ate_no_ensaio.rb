# O "esperar até" no ensaio. Saiu do Ensaio sem mudar nada (a classe passou do tamanho quando os passos que esperam
# resposta, #2931/#2935/#2936, encontraram o ensaio de card, #2631).
#
# Já vale agora: segue na hora, como o motor; com hora marcada (G64), não: o motor só confere na hora. Não vale: os
# caminhos possíveis; sem prazo (#2750), sem o "se vencer". Com o galho "a cada mensagem" (G63), mais um caminho: os
# passos dele, que param no fim com a marca `volta` (o roteiro do ensaio não volta a esperar).
class Autonomia::Automacao::EsperarAteNoEnsaio
  EnquantoEspera = ::Autonomia::Automacao::EnquantoEspera

  # O bloco ensaia um caminho a partir do primeiro passo dele.
  def initialize(roteiro:, &caminho)
    @roteiro = roteiro
    @caminho = caminho
  end

  # [o nó do ensaio, o próximo passo neste caminho (nil quando abriu caminhos)].
  def ensaiar(passo, valores)
    return [no(passo, 'esperar_ate_ja_vale'), @roteiro.seguinte(passo['id'])] if segue_na_hora?(passo, valores)

    ramos = [{ chave: 'chegou', passos: @caminho.call(@roteiro.seguinte(passo['id'])) }]
    ramos << { chave: 'se_vencer', passos: @caminho.call(@roteiro.entrar(passo, 'se_vencer')) } unless sem_prazo?(passo)
    ramos << galho(passo) if EnquantoEspera.a_cada?(passo)
    [no(passo, 'esperar_ate', ramos: ramos), nil]
  end

  private

  def segue_na_hora?(passo, valores)
    !EnquantoEspera.conferir_as?(passo) && ::Autonomia::Automacao::Condicao.new(passo['condicao'], valores).verdadeira?
  end

  def sem_prazo?(passo) = ::Autonomia::Automacao::Duracao.sem_prazo?(passo['prazo'])

  def galho(passo, chave = EnquantoEspera::A_CADA)
    { chave: chave, volta: @roteiro.volta(passo, chave), passos: @caminho.call(@roteiro.entrar(passo, chave)) }
  end

  def no(passo, faria, ramos: nil) = { id: passo['id'], tipo: passo['tipo'], faria: faria, dados: {}, ramos: ramos }.compact
end
