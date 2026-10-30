# IA cuida dos comentários (#2212, B1/B2): o "Ler e mandar" do dono. Os comentários que chegaram antes de ligar o
# cuidado (`started_at`), com até 7 dias (o privado não alcança os mais velhos), vão para a fila do motor como
# comentários novos: cada um no seu CuidarJob, que lê o texto na Meta e decide se é o caso. O motor não repete o que já
# fez (a reserva `ai_seen`). Os argumentos e os jobs levam só ids.
#
# A Meta fora do ar tenta de novo poucas vezes (TENTATIVAS). Esgotado, ou com uma recusa que não passa com o tempo (sem
# permissão), o job solta a marca `read_old_at` (Painel#ler_antigos!): o botão volta e o dono pode tentar de novo. O
# mesmo quando o perfil, a conexão ou o anúncio não existem mais (`not_found`), ou quando a leitura do anúncio falha
# antes de chegar aos comentários (AdManagement::Error).
class Crm::MetaAds::ComentariosIa::LerAntigosJob < ApplicationJob
  # A Meta não respondeu à leitura dos comentários.
  class MetaIndisponivel < StandardError; end

  TENTATIVAS = 3
  PASSAGEIRO = 'meta_unavailable'.freeze
  SUMIU = 'not_found'.freeze

  queue_as :low
  retry_on MetaIndisponivel, attempts: TENTATIVAS, wait: 1.minute do |job, _erro|
    soltar!(*job.arguments, PASSAGEIRO)
  end

  def self.soltar!(account_id, alvo, status)
    care = Crm::MetaAds::ComentariosIa::Painel.cuidado_do(account_id, alvo)
    return if care.nil?

    # Sem validar: um cuidado que não passaria na validação de hoje não pode deixar o "Ler e mandar" travado.
    care.update_columns(read_old_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.warn("[comentarios_ia] ler_antigos solto account=#{account_id} care=#{care.id} status=#{status}")
  end

  def perform(account_id, alvo)
    account = Account.find_by(id: account_id)
    care = account && Crm::MetaAds::ComentariosIa::Painel.cuidado_do(account.id, alvo)
    return if care.nil?

    lido = ler(account, alvo)
    return enfileirar_antigos(account, alvo.to_h.stringify_keys, care, lido[:linhas]) if lido[:status] == 'ready'
    raise MetaIndisponivel if lido[:status] == PASSAGEIRO

    self.class.soltar!(account_id, alvo, lido[:status])
  end

  private

  def ler(account, alvo)
    fonte = Crm::MetaAds::ComentariosIa::Fonte.do_alvo(account, alvo)
    fonte ? fonte.ler : { status: SUMIU }
  rescue Crm::MetaAds::AdManagement::Error => e
    { status: e.code }
  end

  def enfileirar_antigos(account, alvo, care, linhas)
    linhas.each { |linha| enfileirar(account, alvo, linha) if recente?(linha) && linha[:momento] < care.started_at }
  end

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
