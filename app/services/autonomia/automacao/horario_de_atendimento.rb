# #2503: a conversa está dentro do horário de atendimento da caixa dela, como valor fechado da receita
# (`conversa.no_horario`, sim/não): o "Só se" e o "se" da receita "Responder fora do horário".
#
# Pergunta à própria caixa (Inbox#working_now?, a mesma regra da resposta automática de fora do horário), sem refazer
# a conta: os dias e as horas da caixa, no fuso dela, que com o horário único da caixa (#1619, flag
# `horario_unico_caixa`) é o fuso da conta. Nunca um fuso fixo. A caixa sem horário de atendimento ligado está sempre
# no horário: não há fora do horário para avisar.
#
# Lido na hora em que a condição é conferida: no "Só se" do gatilho, quando a mensagem chega; num "se" depois de uma
# espera, quando o passo roda; no ensaio, agora.
#
# Fica fora do Valores pelo tamanho dele, no padrão da Ausencia: entra nos CAMPOS e as opções fechadas nos FECHADOS.
module Autonomia::Automacao::HorarioDeAtendimento
  VALORES = { 'conversa.no_horario' => ->(conversa) { conversa.inbox.working_now? } }.freeze

  FECHADOS = VALORES.keys.index_with { { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] } }.freeze
end
