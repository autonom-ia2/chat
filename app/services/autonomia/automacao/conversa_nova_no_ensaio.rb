# A conversa em que o ensaio age no alvo sem conversa própria (#2680): o card sem conversa principal (CardsDoEnsaio) e
# o contato (ContatosDoEnsaio). Com a caixa da conversa nova no gatilho, o motor usa a conversa do contato nessa caixa
# (Contexto#conversa_nova) ou, sem ela, o passo "mensagem" abre uma. Quem inclui tem `@conta`, `@gatilho` e `contexto`
# (o de quem ensaia, para as políticas).
module Autonomia::Automacao::ConversaNovaNoEnsaio
  # [a conversa, quando há e quem ensaia a vê; senão nil] e [a caixa por onde a mensagem abriria, quando não há
  # conversa]. Sem a caixa ou sem contato, [nil, nil].
  def conversa_nova(contato)
    caixa = ::Autonomia::Automacao::ConversaNova.caixa(@conta, @gatilho.dig('conversa_nova', 'caixa_id'))
    return [nil, nil] if caixa.nil? || contato.nil?

    existente = ::Autonomia::Automacao::ConversaNova.existente(caixa, contato)
    existente && ConversationPolicy.new(contexto, existente).view? ? [existente, nil] : [nil, caixa]
  end
end
