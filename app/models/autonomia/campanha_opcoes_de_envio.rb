# As opções de envio de uma campanha da jornada (#3101), numa tabela do fork: WhatsApp Oficial e SMS (Campaign),
# WhatsApp API (WhatsappApiCampaign) e e-mail (EmailCampaign). Sem linha, nada muda: tudo desligado.
# - melhor_horario: cada pessoa recebe na hora em que costuma responder (Autonomia::MelhorHorario).
# - reenvio_*: a segunda mensagem para quem não respondeu (CampaignJourney::Reenvio). `reenvio_campanha` é a campanha
#   que ela gerou.
class Autonomia::CampanhaOpcoesDeEnvio < ApplicationRecord
  self.table_name = 'campanha_opcoes_de_envio'

  belongs_to :account
  belongs_to :campanha, polymorphic: true
  belongs_to :reenvio_campanha, polymorphic: true, optional: true
end
