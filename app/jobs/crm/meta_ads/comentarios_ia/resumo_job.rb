# IA cuida dos comentários (#2212, A2): conta o "O que tem nos comentários" fora do pedido da tela, que pergunta de
# novo até a conta ficar pronta (Resumo). Os argumentos são só ids: o comentário é lido de novo aqui.
class Crm::MetaAds::ComentariosIa::ResumoJob < ApplicationJob
  queue_as :low

  def perform(account_id, alvo)
    account = Account.find_by(id: account_id)
    return if account.nil?

    Crm::MetaAds::ComentariosIa::Resumo.new(account: account, alvo: alvo).contar!
  end
end
