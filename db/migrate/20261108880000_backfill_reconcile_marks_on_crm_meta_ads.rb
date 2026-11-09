# #2740 (decisão do Rodrigo): o formulário com destino e a Página recebendo de antes do #2285 ficaram sem marco de
# início, e a reconciliação não os relia. O marco passa a ser o momento do deploy (esta migration): daqui para a frente a
# reconciliação traz o lead que o webhook perdeu, e não relê nenhum lead de antes do deploy. O webhook não muda: ele
# não olha marco.
# - Só grava onde o marco falta; marco que já existe fica. Rodar de novo não muda nada.
# - Formulário sem destino e Página parada ficam nulos: o marco nasce quando o destino for salvo ou a Página voltar.
# - Poucas linhas (09/11/2026, hub2you: 0 formulários e 0 Páginas recebendo sem marco; as 2 Páginas sem marco estão
#   paradas e ficam nulas. A stack Autonom.ia é contada antes do deploy): sem lotes.
# - O down não desfaz: sem o marco, a reconciliação só voltaria a ignorar esses formulários.
class BackfillReconcileMarksOnCrmMetaAds < ActiveRecord::Migration[7.2]
  Formulario = Class.new(ActiveRecord::Base) { self.table_name = 'crm_meta_ads_lead_forms' }
  Pagina = Class.new(ActiveRecord::Base) { self.table_name = 'crm_meta_ads_pages' }

  def up
    agora = Time.current
    Formulario.where(destination_set_at: nil).where.not(pipeline_id: nil).where.not(stage_id: nil)
              .update_all(destination_set_at: agora) # rubocop:disable Rails/SkipsModelValidations
    Pagina.where(leadgen_receiving_since: nil, leadgen_receiving: true)
          .update_all(leadgen_receiving_since: agora) # rubocop:disable Rails/SkipsModelValidations
  end

  def down; end
end
