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
class Crm::MetaAds::LeadForms::ReconcileScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  LOCK_TTL = 6.hours

  def self.lock_key(form_record_id)
    ['crm_meta_ads_lead_forms', 'reconcile', form_record_id]
  end

  def perform
    Crm::MetaAdsLeadForm.reconcilable.includes(:account).find_each do |form|
      next unless form.account.feature_enabled?(Crm::MetaAds::LeadForms::ImportPastJob::FEATURE)
      next unless Rails.cache.write(self.class.lock_key(form.id), true, expires_in: LOCK_TTL, unless_exist: true)

      Crm::MetaAds::LeadForms::ReconcileJob.perform_later(form.id)
    end
  end
end
