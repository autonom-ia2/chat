json.extract! pipeline, :id, :account_id, :name, :description, :status, :is_default, :position, :counts_as_sale, :when_to_use, :created_at, :updated_at
# Valor de venda (#2075): a meta do mês em R$ (metadata['goals']) só vai para quem tem `sales_value_view`.
json.metadata ::Crm::ValorDeVenda.ve?(Current.account_user) ? pipeline.metadata : pipeline.metadata.to_h.except('goals')
json.created_by_id pipeline.created_by_id
