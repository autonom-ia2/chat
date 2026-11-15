# Um passo da busca dos seguros no conector (E7, #2900; o que fazer está em Carteira::Conector::Sincronizar). Recebe só o
# id da leitura: o identificador do pedido, o ponto da lista e os registros nunca entram na fila.
#
# NÃO DORME: cada execução é UMA chamada ao conector, e o job se reagenda com a espera que o passo devolveu (o mesmo
# desenho de Autonomia::Agents::Tools::AsyncRunJob). Assim a busca de 36 meses, que leva muitos minutos na plataforma da
# corretora, não segura worker, e um deploy no meio só adia o próximo passo. Sem nova tentativa automática do Sidekiq:
# repetir o passo é a própria busca que decide (Sincronizar conta as tentativas), e a busca parada volta pela tela.
class Carteira::Conector::BuscaJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(leitura_id)
    leitura = Carteira::Leitura.do_conector.find_by(id: leitura_id)
    return unless leitura&.estado == 'lendo'

    espera = Carteira::Conector::Sincronizar.new(leitura).passo
    self.class.set(wait: espera).perform_later(leitura_id) if espera
  end
end
