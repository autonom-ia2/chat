# #3101: editar a primeira campanha antes de a segunda mensagem sair cancela a segunda (CampaignJourney::Reenvio): o
# texto, o modelo, a caixa ou a data que valiam quando ela foi escolhida mudaram. Só renomear não cancela. Incluído em
# Campaign (WhatsApp Oficial e SMS) e EmailCampaign por config/initializers/campaign_journey.rb. A WhatsApp API não tem
# edição; cancelar (lá e no e-mail) e apagar a campanha a varredura percebe sozinha (CampaignJourney::Reenvio::Varredura).
module CampaignJourney::Reenvio::Cancelavel
  extend ActiveSupport::Concern

  # O que muda a mensagem ou quando ela sai, por modelo. Fora daqui não cancela: o nome (a segunda leva o nome que a
  # primeira tiver quando ela for criada), a situação, os contadores e as datas do envio.
  EDITAVEIS = {
    'Campaign' => %w[message template_params inbox_id scheduled_at],
    'EmailCampaign' => %w[subject preheader body_html body_mjml]
  }.freeze

  included do
    after_update_commit :cancelar_reenvio, if: :editada_para_o_reenvio?
  end

  private

  def editada_para_o_reenvio?
    saved_changes.keys.intersect?(EDITAVEIS.fetch(self.class.name, []))
  end

  def cancelar_reenvio
    CampaignJourney::Reenvio.cancelar!(self)
  end
end
