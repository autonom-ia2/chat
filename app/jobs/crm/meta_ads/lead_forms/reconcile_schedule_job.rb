# Reconciliação dos formulários da Meta (#2285), chamada pelo sidekiq-cron (config/schedule.yml) a cada hora: lead que
# o webhook leadgen não trouxe (a Meta fora do ar mais que as tentativas do FacebookLeadgenJob) entra sozinho.
#
# Para cada formulário com destino num funil ativo, na Página que a conta está recebendo e com `meta_ads_formularios`
# ligada, enfileira um ReconcileJob. A trava por formulário garante uma leitura por formulário por rodada: o job da
# rodada anterior ainda na fila não ganha outro.
#
# A trava sai no fim do ReconcileJob (ensure); o prazo só vale se o job nunca rodar (processo morto, job perdido).
# Bem maior que o intervalo entre rodadas, para a fila atrasada não empilhar jobs do mesmo formulário; bem menor que a
# janela de 48 h do ReconcileJob, para o formulário voltar a ser lido antes de algum lead sair dela.
#
# Conta com `meta_ads_formularios` desligada: o webhook ignora o lead dela, então a Página não está recebendo de fato.
# A cada rodada, o marco leadgen_receiving_since das Páginas dela anda para agora; quando a flag volta, a reconciliação
# não relê o período em que ela esteve desligada. Precisão de uma rodada (1 hora): o que caiu entre a última rodada com
# a flag desligada e o instante em que ela voltou pode ser relido.
class Crm::MetaAds::LeadForms::ReconcileScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  LOCK_TTL = 6.hours

  def self.lock_key(form_record_id)
    ['crm_meta_ads_lead_forms', 'reconcile', form_record_id]
  end

  def perform
    paused = Set.new
    Crm::MetaAdsLeadForm.reconcilable.includes(:account).find_each do |form|
      next paused << form.account_id unless form.account.feature_enabled?(Crm::MetaAds::LeadForms::ImportPastJob::FEATURE)
      next unless Rails.cache.write(self.class.lock_key(form.id), true, expires_in: LOCK_TTL, unless_exist: true)

      Crm::MetaAds::LeadForms::ReconcileJob.perform_later(form.id)
    end
    hold_paused(paused)
  end

  private

  # Só o marco, sem callbacks: a Página continua assinada e volta a receber quando a flag voltar.
  def hold_paused(account_ids)
    return if account_ids.empty?

    Crm::MetaAdsPage.leadgen_receiving.where(account_id: account_ids.to_a).where.not(leadgen_receiving_since: nil)
                    .update_all(leadgen_receiving_since: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
