# As empresas da gaveta "Mais filtros" da Lista nova de Relacionamentos (#2894), por nome, só com Empresas ligado na conta.
module Enterprise::Relacionamentos::OpcoesDeFiltro
  private

  def empresas
    return super unless @account.feature_enabled?('companies')

    por_nome = Arel.sql(::Relacionamentos::Consulta.por_nome('companies'))
    @account.companies.order(por_nome).pluck(:id, :name).map { |id, name| { value: id, label: name } }
  end
end
