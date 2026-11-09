# A rede de segurança da campanha da vez (#2414 G55): a conferência marcada da vez (CampanhaDaOcorrencia), a cada REDE
# enquanto a vez está aberta, com a regra da rede (a execução travada e o lote que não rodou contam como fora; a que
# espera segura). Também é a nova tentativa depois de um erro ao mandar (TENTAR_DE_NOVO). Uma marca
# só por vez: o job que acorda fora da hora marcada, ou com a vez fechada, não faz nada.
class Autonomia::Automacao::FecharVezJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(vez_id)
    ::Autonomia::Automacao::CampanhaDaOcorrencia.conferencia_marcada(vez_id)
  end
end
