# #2503: a conversa está dentro do horário de atendimento da caixa dela, como valor fechado da receita
# (`conversa.no_horario`, sim/não): o "Só se" e o "se" da receita "Responder fora do horário".
#
# Pergunta à regra única do horário da caixa (Autonomia::Agents::Operate::HorarioDaCaixa, #1691), a mesma da agente de
# IA em "Só no horário"/"Só fora do horário": o motor e a IA nunca discordam sobre a caixa estar aberta. Com o horário
# único da caixa (#1619, flag `horario_unico_caixa`) é o horário de atendimento da caixa no fuso da conta; sem a flag,
# o calendário de caixa do CRM, quando existe, manda. Nunca um fuso fixo. A caixa sem horário nenhum está sempre no
# horário (`aberta_agora` nil): não há fora do horário para avisar.
#
# Lido na hora em que a condição é conferida: no "Só se" do gatilho, quando a mensagem chega; num "se" depois de uma
# espera, quando o passo roda; no ensaio, agora.
#
# Fica fora do Valores pelo tamanho dele, no padrão da Ausencia: entra nos CAMPOS e as opções fechadas nos FECHADOS.
module Autonomia::Automacao::HorarioDeAtendimento
  VALORES = {
    'conversa.no_horario' => ->(conversa) { ::Autonomia::Agents::Operate::HorarioDaCaixa.new(conversation: conversa).aberta_agora != false }
  }.freeze

  FECHADOS = VALORES.keys.index_with { { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] } }.freeze
end
