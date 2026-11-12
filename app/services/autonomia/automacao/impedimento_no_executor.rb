# O que impede uma execução de andar agora, no Executor (#2414 F3): o motor, a automação ligada, a flag dos gatilhos de
# card, o alvo, o Spam e quem ligou. Saiu do Executor sem mudar nada (#2931: a classe passou do tamanho com os passos que
# esperam resposta). Usa os métodos dele (encerrar, registrar, pausar, alvo, contexto, motivo_de_quem_ligou) e o estado
# da rodada (@execucao, @marca, @definicao, @account, @parou).
module Autonomia::Automacao::ImpedimentoNoExecutor
  Execucao = ::Autonomia::Automacao::Execucao

  private

  # Fecha a execução e devolve true quando ela não pode andar agora. A execução que já não é desta rodada (a varredura a
  # fechou como travada, alguém a desligou) para sem gravar nada na execução.
  def impedida?(passo_id)
    return parou_por_fora(passo_id) unless desta_rodada?

    estado, motivo = impedimento
    encerrar(passo_id, estado, motivo) if estado
    estado.present?
  end

  # Parada no meio da rodada (o desligar, o "Parar para este card" do #2499): quem parou não registra a execução que está
  # andando (o cursor dela não diz o passo, Execucao.parar_por_fora!) e deixa o porquê nela; o registro fica aqui, no
  # passo em que a rodada ia (#2750, revisão). Sem porquê deixado, nada: a varredura que a fechou como travada, ou a
  # outra rodada que a fechou pelo impedimento (o job velho), já deixou o registro dela.
  def parou_por_fora(passo_id)
    @parou = true
    motivo = Execucao.where(id: @execucao.id, estado: 'parada').pick(:textos)&.dig(Execucao::PORQUE)
    registrar(passo_id, 'pulado', motivo) if motivo
    true
  end

  # [estado final, motivo] quando a execução não pode andar agora; nil quando pode.
  def impedimento
    return %w[parada motor_desligado] unless ::Autonomia::Automacao::Motor.ligado?(@account)
    return %w[parada desligada] unless @definicao.ativa
    # #2499: a flag dos gatilhos de card desligada é o rollback da F6; a execução aberta de gatilho de card fecha.
    return %w[parada gatilho_desligado] unless ::Autonomia::Automacao::Gatilhos.disponivel?(@execucao.chave_gatilho, @account)
    return %w[interrompida alvo_sumiu] unless alvo_da_conta?
    return %w[parada spam] if contexto.no_spam?

    motivo = motivo_de_quem_ligou
    ['parada', pausar(motivo)] if motivo
  end

  def alvo_da_conta? = alvo.present? && contexto.conta_id == @account.id

  def desta_rodada? = Execucao.exists?(id: @execucao.id, estado: 'andando', travada_em: @marca)
end
