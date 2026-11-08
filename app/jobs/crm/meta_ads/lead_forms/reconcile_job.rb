# Relê um formulário (#2285) e traz para o destino quem ainda não entrou. Reaproveita o PastLeads e o Importer, que não
# duplica pelo leadgen_id: o lead que o webhook já trouxe volta :duplicate.
#
# Lê desde o mais recente entre: as últimas WINDOW, o destino salvo (destination_set_at) e a Página voltar a receber
# nesta conta (leadgen_receiving_since). Assim só traz o que o webhook traria: quem preencheu antes de salvar o destino
# (sem "trazer quem já preencheu") ou com a Página parada fica de fora. Marco nulo (linha de antes do #2285) não chega
# aqui: o scope reconcilable o deixa de fora até o destino ser salvo de novo.
#
# A janela cobre bem mais que o intervalo entre rodadas (1 hora): Meta fora do ar agora, a próxima rodada relê as mesmas
# horas. Por isso a queda não tenta de novo aqui; só fica no log. Recusa da Meta (token, permissão) vai ao rastreador:
# sem ela resolvida, a reconciliação não traz ninguém. A trava da rodada sai no fim, dê certo ou não.
class Crm::MetaAds::LeadForms::ReconcileJob < ApplicationJob
  queue_as :low

  WINDOW = 48.hours

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

    result = past.import!(pipeline: form.pipeline, stage: form.stage)
    Rails.logger.info("[MetaAds::LeadForms::Reconcile] form_id=#{form.form_id} imported=#{result[:imported]}") if result[:imported].positive?
  rescue Crm::MetaAds::LeadForms::Unavailable
    Rails.logger.warn("[MetaAds::LeadForms::Reconcile] Meta fora do ar (form_id=#{form.form_id}); a próxima rodada relê")
  rescue Crm::MetaAds::LeadForms::Error => e
    refused = StandardError.new("Reconciliação do formulário recusada pela Meta (form_id=#{form.form_id}, code=#{e.code})")
    ChatwootExceptionTracker.new(refused, account: form.account).capture_exception
  end
end
