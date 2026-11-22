# #3098: grava o que a revisão da campanha escolheu em "Quem comprou depois" (a janela de compra e o grupo de
# controle) e sorteia o grupo. Roda quando a campanha é confirmada: na criação (WhatsApp Oficial, SMS, WhatsApp API)
# ou, no e-mail, antes de agendar ou enviar (o link do e-mail nasce no Passo 2, antes da revisão).
#
# Sem as chaves, a campanha fica com o padrão (7 dias, sem grupo): a automação e quem não abre a linha medem igual.
#
# O público do sorteio é o "Vão receber" do preview (CampaignJourney::RecipientPreview#receive_ids), com as mesmas
# variáveis da campanha: quem seria pulado por falta de variável, recusa ou e-mail suprimido não entra no grupo, e o
# número da revisão bate com o do envio. Roda dentro da transação de quem chama, com o link travado.
class CampaignJourney::Medicao
  def self.permitidos(params)
    params.to_h.with_indifferent_access.slice(:janela_de_compra_dias, :grupo_de_controle_pct).compact
  end

  # Quem vai receber a campanha do link, pelas regras do preview do canal (`whatsapp_cloud`, `whatsapp_api`, `sms`,
  # `email`).
  def self.publico(link, canal)
    campaign = link.campaign
    CampaignJourney::RecipientPreview.new(
      link.campaign_import, channel: canal, variable_bindings: link.variable_bindings, variable_defaults: link.variable_defaults,
                            message_body: campaign.try(:message_body) || campaign.try(:message)
    ).receive_ids
  end

  def initialize(link)
    @link = link
  end

  # `escolhas`: { janela_de_compra_dias, grupo_de_controle_pct } (as que vierem). `publico`: os contact_ids de quem
  # ia receber, para o sorteio, vêm do bloco (só chamado se houver grupo).
  def aplicar!(escolhas)
    escolhas = self.class.permitidos(escolhas)
    @link.lock!
    @link.update!(escolhas) if escolhas.any?
    # Antes do envio (o e-mail volta à revisão e muda a porcentagem): o sorteio antigo sai e vale o novo.
    grupo = CampaignJourney::GrupoDeControle.new(@link)
    grupo.apagar! if @link.saved_change_to_grupo_de_controle_pct?
    grupo.sortear!(yield) if grupo.ativo?
  end
end
