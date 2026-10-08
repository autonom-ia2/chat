# Funil que conta como venda (#1144): quando ligado (padrão, como sempre foi), fechar com sucesso é venda (won/lost,
# receita, taxa de ganho, conversões Meta/Google). Desligado, o funil é de outra área (sinistro, cobrança, suporte...)
# e o desfecho grava resolved/cancelled, que nenhum relatório de venda nem conversão conta.
class AddCountsAsSaleToCrmPipelines < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_pipelines, :counts_as_sale, :boolean, default: true, null: false
  end
end
