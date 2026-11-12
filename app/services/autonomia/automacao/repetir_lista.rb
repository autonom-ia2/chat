# #2932 — "Fazer para cada um de uma lista": cada item da lista (ItensDaLista) ganha uma execução própria, a "filha da
# lista", que roda os passos do galho `cada` com o item como alvo. A mãe não espera: entrega a lista ao RepetirListaJob,
# que abre as filhas fora da rodada dela (FilhasDaLista), e segue.
#
# A filha da lista, como a do "em outro registro" (G18):
# - é marcada pelo `evento` (`lista:<mãe>:<base>:<id do item>:<passo>`); o índice único (automacao_id, evento) garante
#   uma execução só por item e por rodada da mãe, e o índice das abertas, uma só por item e automação: o item que já
#   está no meio desta automação fica de fora (`ja_aberta`), sem laço;
# - herda a cadeia e a profundidade da mãe (D6): o que ela muda não redispara a própria automação;
# - anda só no galho `cada` (Roteiro.da) e passa por tudo que o alvo passa, a cada ação (Executor#impedimento): conta,
#   quem ligou, alcance e, no card, a chave de funis (Acesso#motivo_no).
# Dentro do galho não cabe outro "para cada" nem "em outro registro": a filha nunca abre netas.
module Autonomia::Automacao::RepetirLista
  TIPO = 'repetir_lista'.freeze
  RAMO = 'cada'.freeze
  MARCA = 'lista'.freeze
  BASES = { 'Contact' => 'contato', 'Crm::Card' => 'card' }.freeze
  TETO_MAXIMO = 200

  module_function

  def do_tipo?(passo) = passo['tipo'] == TIPO

  def marca(mae, item, passo_id) = [MARCA, mae.id, BASES.fetch(item.class.name), item.id, passo_id].join(':')

  # [id da mãe, id do passo] da filha da lista; nil nas outras execuções. O id do passo vai por último: ele pode ter ":".
  def da(execucao)
    prefixo, mae_id, _base, _id, passo_id = execucao&.evento.to_s.split(':', 5)
    [mae_id.to_i, passo_id] if prefixo == MARCA && passo_id.present?
  end

  # A execução roda no galho de um passo da mãe ("em outro registro" ou "para cada")? Ela nunca abre netas.
  def filha?(execucao) = (::Autonomia::Automacao::EmOutroRegistro.da(execucao) || da(execucao)).present?

  # Ela ou uma execução acima dela (a do bloco que uma filha chamou, #2933) é filha? Então não abre netas: o bloco não
  # fura a regra. O bloco pode mudar depois de a mãe salvar, e o salvar não alcança essa mudança.
  def dentro_de_filha?(execucao) = filha?(execucao) || ::Autonomia::Automacao::Bloco.acima(execucao).any? { |uma| filha?(uma) }
end
