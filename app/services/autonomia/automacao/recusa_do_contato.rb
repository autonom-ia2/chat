# Quem não recebe nada da automação (decisão 5 do Rodrigo, #2414): o contato bloqueado e o que pediu para não receber
# mensagens ativas. A regra é a das campanhas (#2794, Contact.campaign_refusal_now), relida do banco logo antes de cada
# envio: quem foi bloqueado no meio da execução também não recebe. Um ponto só para os passos que falam com o contato:
# a mensagem (e o "escrever", que pergunta à mensagem antes de pagar a IA), o e-mail e a conversa nova.
#
# O motivo é o que o histórico e o ensaio mostram: 'contato_nao_recebe' (pediu para não receber; quem tem os dois conta
# como esse, como na campanha) ou 'contato_bloqueado'. nil = pode receber.
module Autonomia::Automacao::RecusaDoContato
  MOTIVOS = {
    ::ContactCampaignReach::OPTED_OUT => 'contato_nao_recebe',
    ::ContactCampaignReach::BLOCKED => 'contato_bloqueado'
  }.freeze

  module_function

  def motivo(contato_id) = MOTIVOS[::Contact.campaign_refusal_now(contato_id)]
end
