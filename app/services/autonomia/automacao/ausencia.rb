# G23 (#2743): a pessoa responsável está ausente agora (o "ausente até" dela na conta da execução ainda não passou,
# AusenciaDaPessoa), como valor da receita: o "se" que decide se a responsável voltou de férias. Lê o responsável da
# conversa ou o dono do card. Sem responsável, lê false.
#
# Fica fora do Valores pelo tamanho dele, no padrão do Envio e da Resposta, mas entra nos CAMPOS (vale em qualquer
# lugar da receita, sem a janela do "esperar até": não é resposta). As opções fechadas entram nos FECHADOS.
module Autonomia::Automacao::Ausencia
  VALORES = {
    'conversa.responsavel_ausente' => ->(conversa) { ::AccountUser.ausente_na_conta?(conversa.account_id, conversa.assignee_id) },
    'card.responsavel_ausente' => ->(card) { ::AccountUser.ausente_na_conta?(card.account_id, card.owner_id) }
  }.freeze

  FECHADOS = VALORES.keys.index_with { { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] } }.freeze
end
