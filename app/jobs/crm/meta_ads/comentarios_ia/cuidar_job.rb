# IA cuida dos comentários (#2212): um comentário novo, fora do webhook. O Jev e a Meta respondem em segundos; o
# webhook não pode esperar.
#
# Os argumentos são só ids (Comentario#para_o_job): o Sidekiq os guarda em claro no Redis. Se a Meta não responde à
# leitura do comentário, o job tenta de novo, até TENTATIVAS vezes; depois, o comentário fica descartado (a reserva
# `ai_seen` é gravada) e não volta à fila.
class Crm::MetaAds::ComentariosIa::CuidarJob < ApplicationJob
  queue_as :low

  TENTATIVAS = 5

  retry_on Crm::MetaAds::ComentariosIa::Rede::Indisponivel, wait: :polynomially_longer, attempts: TENTATIVAS do |job, _erro|
    comentario = Crm::MetaAds::ComentariosIa::Comentario.new(**job.arguments.first.symbolize_keys)
    Crm::MetaAds::ComentariosIa::Registro.reservar!(comentario)
  end

  def perform(dados)
    Crm::MetaAds::ComentariosIa::Cuidar.new(Crm::MetaAds::ComentariosIa::Comentario.new(**dados.symbolize_keys)).call
  end
end
