# "Trazer minha lista" (#2896): tira um anexo da importação e apaga o arquivo dele do armazenamento.
#
# O anexo sai na hora, dentro da transação de quem chama. O arquivo só é mandado apagar depois que TODAS as transações
# abertas terminam: o job que apaga roda noutra conexão do banco, e se entrasse na fila antes do commit ainda veria o
# anexo, desistiria em silêncio (é o que `ActiveStorage::Blob#purge` faz com arquivo que ainda tem anexo) e o arquivo
# ficaria no armazenamento sem dono, para sempre e fora do alcance de ContactImports::Trazer::AnexosVencidos. Por isso
# nada aqui usa `purge_later` do anexo, que põe o job na fila na hora.
#
# Se a transação volta atrás, o anexo volta junto e nada é apagado.
#
# Trocar um anexo por outro (`attach` em cima do que já existe) não passa por aqui: o Rails destrói o anexo antigo e
# manda apagar o arquivo dele depois do commit (`after_destroy_commit` do ActiveStorage::Attachment).
module ContactImports::Trazer::ApagarAnexo
  module_function

  # anexo: o `has_one_attached` da importação (importacao.consertos, importacao.linhas_com_problema, ...).
  def call(anexo)
    return unless anexo.attached?

    arquivo = anexo.blob
    anexo.detach
    ActiveRecord.after_all_transactions_commit { arquivo.purge_later }
  end
end
