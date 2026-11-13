# Fechar a execução, incluído no Executor (saiu dele no #2933, quando o bloco passou a acordar a mãe ao fechar).
module Autonomia::Automacao::FimNoExecutor
  private

  # Fecha a execução. Com `resultado`, deixa antes o registro do passo em que ela parou; depois de `pausar`, marcado
  # como pausa para a tela (Registro::PAUSOU).
  def encerrar(passo_id, estado, motivo, resultado = 'pulado', dados = {})
    dados = dados.merge(::Autonomia::Automacao::Registro::PAUSOU => true) if @pausou
    registrar(passo_id, resultado, motivo, dados) if resultado
    finalizar(estado)
    nil
  end

  # Fechou nesta rodada: a cobertura da agente de IA que ainda valer devolve a conversa à pessoa (decisão 18).
  # G55: a execução que fecha deixa de segurar a campanha da vez do recorrente de card ou contato; confere se ela fecha.
  # #2933: a execução de um bloco que fecha acorda a mãe que espera nela.
  def finalizar(estado)
    gravou = gravar(estado: estado, travada_em: nil)
    ::Autonomia::Automacao::Cobertura.encerrar([@execucao.id]) if gravou
    ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(@execucao)
    ::Autonomia::Automacao::Bloco.acordar_mae(@execucao) if gravou
  end
end
