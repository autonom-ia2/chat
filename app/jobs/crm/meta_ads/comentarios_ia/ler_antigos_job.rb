# IA cuida dos comentários (#2212, B1/B2): o "Ler e mandar" do dono. Os comentários que chegaram antes de ligar o
# cuidado, com até 7 dias (o privado não alcança os mais velhos), vão para a fila do motor como comentários novos: cada
# um no seu CuidarJob, que lê o texto na Meta e decide se é o caso. O motor não repete o que já fez (a reserva `ai_seen`).
# Os argumentos e os jobs levam só ids.
class Crm::MetaAds::ComentariosIa::LerAntigosJob < ApplicationJob
  queue_as :low

  def perform(account_id, alvo)
    account = Account.find_by(id: account_id)
    fonte = account && Crm::MetaAds::ComentariosIa::Fonte.do_alvo(account, alvo)
    return if fonte.nil?

    lido = fonte.ler
    return unless lido[:status] == 'ready'

    lido[:linhas].each { |linha| enfileirar(account, alvo.to_h.stringify_keys, linha) if recente?(linha) }
  end

  private

  def enfileirar(account, alvo, linha)
    comentario = Crm::MetaAds::ComentariosIa::Comentario.new(
      network: linha[:network], account_id: account.id, inbox_id: linha[:inbox_id], post_id: linha[:post_id],
      ad_id: alvo['kind'] == 'ad' ? alvo['ad_id'] : nil, comment_id: linha[:id].to_s, created_time: linha[:momento]
    )
    Crm::MetaAds::ComentariosIa::CuidarJob.perform_later(comentario.para_o_job.stringify_keys)
  end

  def recente?(linha)
    linha[:momento].present? && linha[:momento] >= Crm::MetaAds::ComentariosIa::Cuidar::JANELA.ago
  end
end
