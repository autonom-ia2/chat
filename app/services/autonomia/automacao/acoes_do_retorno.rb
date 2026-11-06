# A mesma porta da ação (AcoesDoMotor), liberada só para o passo "criar retorno" (G3, #2629): a lista de ações
# permitidas deixa crm/follow_ups de fora, porque o retorno é passo próprio, com campos que a tela entende.
class Autonomia::Automacao::AcoesDoRetorno < Autonomia::Automacao::AcoesDoMotor
  private

  def garantir_permitida!(acao, _dados = nil)
    raise Recusada, I18n.t('autonomia.automacao.motivos.acao_fora') unless acao.to_s == Autonomia::Automacao::PassoDeRetorno::ACAO
    raise SemPermissao, I18n.t('autonomia.automacao.motivos.quem_ligou_sem_permissao') unless @account_user&.permission_granted?(
      Autonomia::Automacao::Acesso::PERMISSAO
    )
  end
end
