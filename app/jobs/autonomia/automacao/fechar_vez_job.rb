# A rede de segurança da campanha da vez (#2414 G55): a cada REDE, enquanto a vez está aberta, confere com a regra da
# rede (a execução travada e o lote que não rodou contam como fora; a que espera segura). Também é a nova tentativa
# depois de um erro ao mandar (TENTAR_DE_NOVO). A vez já fechada não muda nada; a vez sem chegada para de conferir.
class Autonomia::Automacao::FecharVezJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(vez_id)
    return unless ::Autonomia::Automacao::CampanhaDaVez.exists?(id: vez_id, fechada_em: nil)

    situacao = ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir(vez_id, rede: true)
    self.class.set(wait: ::Autonomia::Automacao::CampanhaDaOcorrencia::REDE).perform_later(vez_id) if situacao == :aberta
  end
end
