# #3101: o motor de campanha pergunta uma vez por campanha se ela pediu o melhor horário (Autonomia::MelhorHorario
# .ligado?, uma consulta) e guarda a resposta para todos os destinatários da rodada. Incluído pelos quatro motores:
# CampaignJourney::RecipientTracking (WhatsApp Oficial e SMS), WhatsappApiCampaigns::DeliveryEngine e os dois do e-mail.
# Cada motor cuida de uma campanha só.
module Autonomia::MelhorHorario::DoMotor
  private

  def melhor_horario_ligado?(campanha)
    @melhor_horario_ligado = Autonomia::MelhorHorario.ligado?(campanha) unless defined?(@melhor_horario_ligado)
    @melhor_horario_ligado
  end
end
