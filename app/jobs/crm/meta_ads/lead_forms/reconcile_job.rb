# Relê um formulário (#2285) e traz para o destino quem ainda não entrou. Reaproveita o PastLeads e o Importer, que não
# duplica pelo leadgen_id: o lead que o webhook já trouxe volta :duplicate.
#
# Lê desde o mais recente entre: as últimas WINDOW, o destino salvo (destination_set_at) e a Página voltar a receber
# nesta conta (leadgen_receiving_since). Assim só traz o que o webhook traria: quem preencheu antes de salvar o destino
# (sem "trazer quem já preencheu") ou com a Página parada fica de fora. Marco nulo não chega aqui: o scope
# reconcilable o deixa de fora. Os formulários com destino e as Páginas recebendo de antes do #2285 ganharam o
# momento do deploy do #2740; sem destino ou com a Página parada, o marco nasce quando voltarem. Funil arquivado e
# reativado: o marco nasce na reativação (Crm::MetaAdsLeadForm.restart_marks!, #2804), e o que ficou de antes de
# arquivar não é relido.
#
# Lead que o banco recusa fica lembrado pelo tipo da recusa (RefusedLeads): passageira volta na rodada seguinte; a do
# destino, quando o funil ou a etapa mudam; a do lead, depois do prazo.
#
# A janela cobre bem mais que o intervalo entre rodadas (1 hora): Meta fora do ar agora, a próxima rodada relê as mesmas
# horas. Por isso a queda não tenta de novo aqui; só fica no log. Token recusado (190) marca a conexão como inválida,
# igual ao webhook (#2740). Outra recusa da Meta (permissão) vai ao rastreador, uma vez por dia por formulário: sem ela
# resolvida, a reconciliação não traz ninguém. A trava da rodada sai no fim.
class Crm::MetaAds::LeadForms::ReconcileJob < ApplicationJob
  queue_as :low

  WINDOW = 48.hours
  REFUSED_NOTICE_TTL = 1.day

  def perform(form_record_id)
    form = Crm::MetaAdsLeadForm.reconcilable.includes(:account, :pipeline, :stage).find_by(id: form_record_id)
    return if form.nil? || !form.account.feature_enabled?(Crm::MetaAds::LeadForms::ImportPastJob::FEATURE)

    reconcile(form, read_since(form))
  ensure
    Rails.cache.delete(Crm::MetaAds::LeadForms::ReconcileScheduleJob.lock_key(form_record_id))
  end

  private

  # Lido na hora em que o job roda, não quando foi agendado: fila atrasada não alarga a janela.
  def read_since(form)
    receiving_since = Crm::MetaAdsPage.where(account_id: form.account_id, page_id: form.page_id).pick(:leadgen_receiving_since)
    [WINDOW.ago, form.destination_set_at, receiving_since].compact.max
  end

  def reconcile(form, since)
    past = Crm::MetaAds::LeadForms::PastLeads.for(account: form.account, page_id: form.page_id, form_id: form.form_id,
                                                  form_name: form.form_name, since: since)
    return if past.nil?

    result = past.import!(pipeline: form.pipeline, stage: form.stage, refused: Crm::MetaAds::LeadForms::RefusedLeads.new(form))
    Rails.logger.info("[MetaAds::LeadForms::Reconcile] form_id=#{form.form_id} imported=#{result[:imported]}") if result[:imported].positive?
    Rails.logger.warn("[MetaAds::LeadForms::Reconcile] form_id=#{form.form_id} leitura parou no teto de páginas") if result[:truncated]
  rescue Crm::MetaAds::LeadForms::Unavailable
    Rails.logger.warn("[MetaAds::LeadForms::Reconcile] Meta fora do ar (form_id=#{form.form_id}); a próxima rodada relê")
  rescue Crm::MetaAds::LeadForms::TokenRefused => e
    token_refused!(form, e)
  rescue Crm::MetaAds::LeadForms::Error => e
    notify_refused(form, e)
  end

  # #2740: como o webhook leadgen, o token recusado marca a conexão. A tela pede para conectar de novo e as próximas
  # rodadas param de chamar a Meta (PastLeads.for só lê de conexão ativa). Sem rastreador: não é defeito nosso.
  def token_refused!(form, error)
    Crm::MetaAdsConnection.active.find_by(account_id: form.account_id)&.mark_invalid!(error.meta_message)
  end

  def notify_refused(form, error)
    key = ['crm_meta_ads_lead_forms', 'reconcile_refused', form.id]
    return unless Rails.cache.write(key, true, expires_in: REFUSED_NOTICE_TTL, unless_exist: true)

    refused = StandardError.new("Reconciliação do formulário recusada pela Meta (form_id=#{form.form_id}, code=#{error.code})")
    ChatwootExceptionTracker.new(refused, account: form.account).capture_exception
  end
end
