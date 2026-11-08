# O passo "criar card" no executor (#2414 G4). Fica fora do Executor para ele seguir sendo a lista dos passos; usa os
# métodos dele (reconferir, impedida?, encerrar, pausar, seguir_depois_da_acao).
module Autonomia::Automacao::CardNoExecutor
  private

  # Reconfere tudo como a ação. Sem a flag dos gatilhos de card (F6) ou sem o CRM, fecha sem criar (rollback). Não
  # repete: o card ou foi criado, ou já existia, ou a etapa sumiu; nada disso muda tentando de novo.
  def passo_de_card(passo)
    reconferir
    return if impedida?(passo['id'])
    return encerrar(passo['id'], 'parada', 'card_desligado') unless ::Autonomia::Automacao::PassoDeCard.ligado?(@account)

    resultado = ::Autonomia::Automacao::PassoDeCard.new(execucao: @execucao, passo: passo, alvo: alvo, acesso: @acesso).executar
    return encerrar(passo['id'], 'parada', pausar(resultado.motivo), 'falhou') if resultado.tipo == :sem_acesso

    seguir_depois_da_acao(passo, resultado)
  end
end
