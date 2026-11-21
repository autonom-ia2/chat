# #3097: preenche o resumo de compras (relacionamentos_compras) de todas as contas que já têm venda, fora do deploy.
# É a mesma rotina diária (Relacionamentos::Compras::VarreduraJob): quem ganha linha agora não dispara automação, porque
# não "entrou" no grupo, já estava nele. Migration separada da que cria a tabela para o job só rodar com ela no banco.
# Nada a desfazer no down: a tabela sai com o down da anterior.
class EnqueuePreencherRelacionamentosCompras < ActiveRecord::Migration[7.2]
  def up
    Relacionamentos::Compras::VarreduraJob.perform_later
  end

  def down; end
end
