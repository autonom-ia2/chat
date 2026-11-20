# As empresas da gaveta "Mais filtros" da Lista nova de Relacionamentos (#2894), por nome, só com Empresas ligado na conta.
# #3078 — e as cidades das empresas, para o "Mais filtros" da aba Empresas: só as que existem nas empresas da conta.
module Enterprise::Relacionamentos::OpcoesDeFiltro
  CIDADE_DA_EMPRESA = Arel.sql("companies.additional_attributes->>'city'")
  # A gaveta mostra uma escolha por cidade; numa conta grande, as primeiras 200 em ordem de nome.
  LIMITE_DE_CIDADES = 200

  def call
    return super unless @account.feature_enabled?('companies')

    super.merge(cidades_das_empresas: como_opcoes(cidades_das_empresas))
  end

  private

  def empresas
    return super unless @account.feature_enabled?('companies')

    por_nome = Arel.sql(::Relacionamentos::Consulta.por_nome('companies'))
    @account.companies.order(por_nome).pluck(:id, :name).map { |id, name| { value: id, label: name } }
  end

  def cidades_das_empresas
    @account.companies.where("#{CIDADE_DA_EMPRESA} <> ''").distinct
            .order(CIDADE_DA_EMPRESA).limit(LIMITE_DE_CIDADES).pluck(CIDADE_DA_EMPRESA)
  end
end
