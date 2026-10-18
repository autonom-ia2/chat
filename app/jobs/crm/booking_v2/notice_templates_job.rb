# Casca do #1612; remover em PR à parte depois que retries e dead do Sidekiq expirarem.
#
# Era o "Criar os modelos na Meta" (v1, #1272), aposentado em #1612: aquele caminho postava na Meta sem o
# `Whatsapp::Templates::Garantir` e sem a autorização do dono (#1585). Os modelos dos avisos agora são os v2
# (`Crm::BookingV2::NoticeTemplateEnsureJob`). O job só nascia do clique do administrador (nenhum cron), mas a fila de
# produção não pôde ser lida: um que ainda esteja na fila, nas tentativas ou no dead sem esta classe faria o Sidekiq
# falhar com classe inexistente. Mesmo nome e mesma assinatura; só registra e sai, sem falar com a Meta.
class Crm::BookingV2::NoticeTemplatesJob < ApplicationJob
  queue_as :default

  def perform(page_id, inbox_id, kinds)
    Rails.logger.info("[crm][booking_v2][notice_templates] retired_job_skipped page_id=#{page_id} inbox_id=#{inbox_id} " \
                      "kinds=#{Array(kinds).size}")
  end
end
