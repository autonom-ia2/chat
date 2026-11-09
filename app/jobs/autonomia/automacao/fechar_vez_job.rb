# A rede de segurança da campanha da vez (#2414 G55): REDE depois de a vez abrir, fecha a que ainda não fechou e manda
# a campanha com quem chegou, com o registro de quantos ficaram de fora (CampanhaDaOcorrencia.fechar_pela_rede). A vez
# já fechada não muda nada.
class Autonomia::Automacao::FecharVezJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(vez_id)
    return unless ::Autonomia::Automacao::CampanhaDaVez.exists?(id: vez_id)

    ::Autonomia::Automacao::CampanhaDaOcorrencia.fechar_pela_rede(vez_id)
  end
end
