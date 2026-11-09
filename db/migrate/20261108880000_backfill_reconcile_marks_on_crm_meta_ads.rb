# #2740 (decisão do Rodrigo): o formulário com destino e a Página recebendo de antes do #2285 ficaram sem marco de
# início, e a reconciliação não os relia. O marco passa a ser o momento do deploy (esta migration): daqui para a frente o
# lead perdido pelo webhook entra sozinho, e nenhum lead de antes do deploy é trazido.
# - Só grava onde o marco falta; marco que já existe fica. Rodar de novo não muda nada.
# - Formulário sem destino e Página parada ficam nulos: o marco nasce quando o destino for salvo ou a Página voltar.
# - Poucas linhas (09/11/2026, hub2you: 0 formulários, 2 Páginas paradas): sem lotes.
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
