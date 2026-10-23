# A trava que põe em fila os arquivamentos de funil de uma conta (#2095): o DELETE com escolhas (Crm::Pipelines::Archiver)
# e o PATCH de status (PipelinesController#save_pipeline!). Com ela, dois arquivamentos ao mesmo tempo não zeram os funis
# ativos nem se cruzam (arquivar P1 levando para P2 e P2 levando para P1).
#
# É uma trava de aplicação (pg_advisory_xact_lock), e não a linha da conta: `accounts FOR UPDATE` choca com o FOR KEY
# SHARE que todo INSERT de tabela filha de accounts pega (cards, atividades, retornos, chaves de idempotência...). Ela
# parava a conta inteira enquanto o arquivamento durava e fechava ciclo com quem já segurava um card e ia gravar uma
# atividade (ActiveRecord::Deadlocked). Esta só enfileira quem pede a mesma trava. Vale até o fim da transação: chamar
# dentro de uma.
module Crm::Pipelines::TravaDeArquivar
  module_function

  def travar!(account_id)
    chave = "crm_pipeline_archive:#{account_id.to_i}"
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', chave])
    )
  end
end
