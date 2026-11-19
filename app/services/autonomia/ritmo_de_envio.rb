# Ritmo de envio ao cliente (#3063, item 2). Decisões do Rodrigo (19/11): quem define o limite de mensagens por cliente e o
# horário de envio é o usuário da plataforma, por conta; o aviso de renovação da carteira fica fora da conta. Fora do
# limite ou do horário a mensagem é adiada, nunca descartada.
#
# - Config: o que a conta escolheu (accounts.settings['ritmo_de_envio']).
# - Porteiro: `quando` diz se a mensagem pode sair agora (nil) ou a partir de que hora; `contar!` grava a que saiu.
# - Varredura: devolve ao envio os destinatários de campanha cujo adiamento venceu e apaga o contador velho.
module Autonomia::RitmoDeEnvio
end
