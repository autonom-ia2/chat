# Limites da Meta para criar modelos (fonte oficial, templates/overview, lida no #1585): 250 modelos por WABA de portfólio
# sem verificação e no máximo 100 criações por hora por WABA. Conferidos antes de pagar a IA e falar com a Meta.
# - 250: a lista guardada da caixa (a WABA inteira). Portfólio verificado aceita 6.000, mas a caixa não diz se é
#   verificado; ficamos no teto menor, e a equipe é avisada (`limite_de_modelos`).
# - 100 por hora: contador no Redis por WABA e hora cheia (caixas irmãs e todos os tipos somam), só das tentativas deste
#   ponto único (a tela de Modelos cria por fora; o que passar disso a Meta recusa, e o `Garantir` devolve
#   `meta_recusou`). `reservar!` conta ANTES da IA: cada tentativa paga conta, deu certo ou não.
module Whatsapp::Templates::EnvioForaDaJanela::Limites
  POR_WABA = 250
  POR_HORA = 100
  HORA = 1.hour.to_i

  module_function

  # nil ou `limite_de_modelos`. Só lê.
  def motivo(inbox)
    'limite_de_modelos' if modelos_na_waba(inbox) >= POR_WABA
  end

  # Conta uma tentativa de criar nesta hora e diz se cabe. A chave nasce com prazo (SET NX EX) e o INCR é atômico: dois
  # jobs ao mesmo tempo nunca passam juntos do teto, e a chave nunca fica sem prazo.
  def reservar!(inbox)
    chave = chave_da_hora(inbox)
    Redis::Alfred.set(chave, 0, nx: true, ex: HORA)
    Redis::Alfred.incr(chave) <= POR_HORA
  end

  def chave_da_hora(inbox)
    "whatsapp_fora_da_janela:criacoes:#{inbox.channel.waba_id}:#{Time.current.utc.strftime('%Y%m%d%H')}"
  end

  def modelos_na_waba(inbox)
    channel = inbox.channel
    Whatsapp::Templates::ChannelList.entries(channel.class.where(id: channel.id).pick(:message_templates)).size
  end
end
