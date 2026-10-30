# IA cuida dos comentários (#2212): um comentário novo, fora do webhook. O Jev e a Meta respondem em segundos; o
# webhook não pode esperar.
#
# Os argumentos são só ids (Comentario#para_o_job): o Sidekiq os guarda em claro no Redis. Se a Meta não responde à
# leitura do comentário, ou o Jev não responde à pergunta, o job tenta de novo, até TENTATIVAS vezes, com espera
# crescente (cerca de 4 horas no total). Depois, o comentário fica com a pessoa: a reserva `ai_seen` e o `ai_unread`
# são gravados (o painel mostra "não cuidei"), com aviso no log só com ids, e ele não volta à fila.
# O privado aceita até 7 dias: 4 horas cobrem uma queda sem segurar o comentário para sempre.
class Crm::MetaAds::ComentariosIa::CuidarJob < ApplicationJob
  queue_as :low

  TENTATIVAS = 10

  retry_on Crm::MetaAds::ComentariosIa::Rede::Indisponivel, TypesafeAi::Decisor::Error,
           wait: :polynomially_longer, attempts: TENTATIVAS do |job, erro|
    comentario = Crm::MetaAds::ComentariosIa::Comentario.new(**job.arguments.first.symbolize_keys)
    Rails.logger.warn("[comentarios_ia] #{erro.class.name} em #{TENTATIVAS} tentativas, comentário fica com a pessoa: " \
                      "account=#{comentario.account_id} network=#{comentario.network} comment=#{comentario.comment_id}")
    registro = Crm::MetaAds::ComentariosIa::Registro
    registro.gravar!(comentario, registro::NAO_CUIDOU) if registro.reservar!(comentario)
  end

  def perform(dados)
    Crm::MetaAds::ComentariosIa::Cuidar.new(Crm::MetaAds::ComentariosIa::Comentario.new(**dados.symbolize_keys)).call
  end
end
