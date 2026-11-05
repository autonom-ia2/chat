# A resposta que chegou durante um "esperar até" (G11 do fechamento do #2414): "até o cliente responder" e "até a
# equipe responder". `espera` é a janela da espera (Range: do começo até o prazo, ou sem fim na primeira conferência);
# só conta o que chegou depois do começo e até o prazo.
#
# - Cliente: mensagem recebida na conversa.
# - Equipe: a mesma régua da IA que responde (Autonomia::Agents::Operate::PessoaDaEquipe): pessoa da equipe escrevendo
#   ao cliente, ou o eco do que ela mandou pelo app do celular. Não contam a nota, o robô, o envio automático em nome
#   de alguém (follow-up, campanha, regra), a mensagem da própria automação nem a que falhou: o cliente não a recebeu.
#   Efeito herdado da régua: na caixa Híbrida, o eco da resposta da IA que chega antes da bolha ter o id físico vira
#   mensagem nova com a marca do celular, e conta como da equipe (PessoaDaEquipe, "ECO DO CELULAR").
module Autonomia::Automacao::Resposta
  module_function

  def cliente?(conversa, espera)
    na_janela(conversa.messages.incoming, espera).exists?
  end

  # O SQL já deixa só o que pode ser pessoa ou eco (público, que não falhou, remetente pessoa ou nenhum); a régua decide.
  def equipe?(conversa, espera)
    equipe = ::Autonomia::Agents::Operate::PessoaDaEquipe
    candidatas = conversa.messages.chat.outgoing.where(sender_type: ['User', nil]).where.not(status: :failed)
    na_janela(candidatas, espera).find_each.any? { |mensagem| equipe.da_pessoa?(mensagem) || equipe.eco_do_celular?(mensagem) }
  end

  def na_janela(mensagens, espera)
    depois = mensagens.where('messages.created_at > ?', espera.begin)
    espera.end ? depois.where('messages.created_at <= ?', espera.end) : depois
  end
end
