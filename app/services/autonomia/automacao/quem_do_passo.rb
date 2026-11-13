# Quem aprova o pedido (#2931) e em qual agenda a reunião entra (#2935): "quem cuida do card", uma pessoa ou um time
# (`{ "de": "responsavel" | "pessoa" | "time", "id": ... }`). Decide na hora do passo, com o responsável de então.
#
# "Quem cuida do card": o dono do card; card sem dono e com time, as pessoas do time; fora do card, quem atende a
# conversa. A pessoa e o time são lidos pela conta (a pessoa que saiu da conta não aparece). A reunião é de uma pessoa
# só: o primeiro da lista.
module Autonomia::Automacao::QuemDoPasso
  module_function

  # As pessoas (User) da escolha, na ordem. `contexto`: o Autonomia::Automacao::Contexto do alvo.
  def pessoas(conta, escolha, contexto)
    escolha = escolha.to_h
    case escolha['de']
    when 'pessoa' then conta.users.where(id: escolha['id']).to_a
    when 'time' then da_conta(conta, conta.teams.find_by(id: escolha['id'])&.members)
    else responsaveis(conta, contexto)
    end
  end

  def responsaveis(conta, contexto)
    card = contexto.card
    return da_conta(conta, [card.owner]) if card&.owner
    return da_conta(conta, card.team.members) if card&.team

    da_conta(conta, [contexto.conversa&.assignee])
  end

  def da_conta(conta, usuarios)
    ids = Array(usuarios).compact.map(&:id)
    ids.empty? ? [] : conta.users.where(id: ids).order(:id).to_a
  end
end
