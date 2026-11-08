# Mitigação temporária (#2454): o Resumo passou a contar na hora, sem job. Esta classe vazia só existe para que um
# ResumoJob que esteja na fila low na hora do deploy não morra por não achar a classe. Não faz nada.
# TODO: remover depois de um ciclo de deploy do #2454 (Issue #2455)
class Crm::MetaAds::ComentariosIa::ResumoJob < ApplicationJob
  queue_as :low

  def perform(*); end
end
