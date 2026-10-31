# IA cuida dos comentários (#2212, A2): conta o "O que tem nos comentários" fora do pedido da tela, que pergunta de
# novo até a conta ficar pronta (Resumo). Os argumentos são só ids: o comentário é lido de novo aqui.
# Sem nova tentativa: repetir gastaria de novo a Meta e a IA. Um erro inesperado vai uma vez para o rastreio; a trava
# do "contando" vence e a próxima pergunta da tela conta de novo.
class Crm::MetaAds::ComentariosIa::ResumoJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(account_id, alvo)
    account = Account.find_by(id: account_id)
    return if account.nil?

    Crm::MetaAds::ComentariosIa::Resumo.new(account: account, alvo: alvo).contar!
  end
end
