# Grava uma busca no conector na carteira (E7, #2900; o que fazer está em Carteira::Conector::Gravar), um bloco por vez:
# recebe só o id da leitura e se reagenda enquanto houver item para gravar. A carteira grande não segura worker, e o
# deploy no meio só adia o próximo bloco: o item que já entrou não é gravado outra vez.
class Carteira::Conector::GravarJob < ApplicationJob
  queue_as :medium
  sidekiq_options retry: false

  def perform(leitura_id)
    leitura = Carteira::Leitura.do_conector.find_by(id: leitura_id)
    return unless leitura&.estado == 'trazendo'

    self.class.perform_later(leitura_id) if Carteira::Conector::Gravar.new(leitura).call == :continua
  end
end
