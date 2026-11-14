# Lê um arquivo de uma leitura de PDF da carteira (E6, #2899): o anexar de um seguro e cada PDF do Trazer por PDFs. O
# argumento é só o id do item (Carteira::LeituraItem): CPF, nome, texto e caminho de arquivo nunca entram na fila. O
# trabalho é do Carteira::LerItem.
#
# Sem nova tentativa: cada leitura é uma chamada paga, e o item que falhou já diz "não deu para ler" na tela, com o
# que fazer (mandar de novo). O item que demorou demais na fila fica `falhou` (Carteira::LerItem::PRAZO).
class Carteira::LeituraJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(item_id)
    item = Carteira::LeituraItem.find_by(id: item_id)
    Carteira::LerItem.new(item).call if item
  end
end
