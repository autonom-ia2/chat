# IA cuida dos comentários (#2212): um comentário novo, fora do webhook. O Jev e a Meta respondem em segundos; o
# webhook não pode esperar.
class Crm::MetaAds::ComentariosIa::CuidarJob < ApplicationJob
  queue_as :low

  def perform(dados)
    Crm::MetaAds::ComentariosIa::Cuidar.new(Crm::MetaAds::ComentariosIa::Comentario.new(**dados.symbolize_keys)).call
  end
end
