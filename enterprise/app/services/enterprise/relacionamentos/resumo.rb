# As empresas na frase do topo da Lista nova de Relacionamentos (#2894), só com Empresas ligado na conta.
module Enterprise::Relacionamentos::Resumo
  private

  def empresas
    return super unless @account.feature_enabled?('companies')

    contagens = ::Relacionamentos::ConsultaDeEmpresas.new(@account, {}).contagens
    { total: contagens['todas'], sem_conversa_3_meses: contagens['sem_conversa_3_meses'] }
  end
end
