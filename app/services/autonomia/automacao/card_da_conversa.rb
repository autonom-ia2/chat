# O card que a automação de conversa lê (#2716): o assunto atual da conversa, a mesma regra do selo da lista
# (Crm::Cards::ConversationCardFinder: o aberto antes do encerrado, depois o foco mais recente). Só para ler: no "Só se",
# nos filtros, nos textos e copiando um campo dele. O que apontaria a ação para o card (`card.*` no caminho, `card.id`
# no corpo) o salvar recusa (`card_da_conversa_so_le`); mexer no card é o passo "em outro registro".
# O valor protegido do card (`card.valor`) só decide, no "Só se" e nas condições: nem texto nem corpo, em qualquer
# automação (#2780).
#
# Ler pede a chave de funis (RegraDoFunil.chave?: `crm_manage_pipelines` ou `crm_admin`) de quem salva (controller) e de
# quem ligou (Acesso pausa sem ela), como o gatilho de card. Ao rodar, sem a chave ou sem card que ele veja (Crm::CardPolicy)
# na conversa, lê vazio; entre os cards da conversa, vale o primeiro que ele vê.
module Autonomia::Automacao::CardDaConversa
  module_function

  ID = 'card.id'.freeze
  NA_ACAO = %i[caminho corpo].freeze
  ESCREVE = %i[corpo texto].freeze

  # O caminho lê o card a partir de uma conversa?
  def do_caminho?(caminho, alvo_type) = alvo_type == 'Conversation' && caminho.to_s.split('.', 2).first == 'card'

  # Na ação (`onde`: :caminho ou :corpo), o caminho apontaria a ação para o card da conversa?
  def age?(caminho, onde, alvo_type)
    do_caminho?(caminho, alvo_type) && (onde == :caminho || caminho.to_s == ID)
  end

  # O que o salvar recusa no caminho, pelo lugar em que ele é lido (`onde`: :caminho ou :corpo da ação, :texto; nil é
  # decidir), no gatilho da receita (`gatilho`: o tipo): a ação que apontaria para o card da conversa, e o valor
  # protegido escrito num corpo ou num texto, que só decide em qualquer automação (#2780, Valores.so_decide?).
  # Devolve a chave da frase, ou nil.
  def problema(caminho, onde, gatilho)
    return :card_da_conversa_so_le if NA_ACAO.include?(onde) && age?(caminho, onde, ::Autonomia::Automacao::Gatilhos.alvo(gatilho))

    :valor_protegido_so_decide if ESCREVE.include?(onde) && ::Autonomia::Automacao::Valores.so_decide?(caminho)
  end

  # Algum `$valor` da receita lê o card? Anda pela receita inteira (gatilho, filtros, condições, textos, caminhos e
  # corpos).
  def le?(trecho)
    case trecho
    when Hash then trecho.any? { |chave, valor| (chave.to_s == '$valor' && valor.to_s.start_with?('card.')) || le?(valor) }
    when Array then trecho.any? { |item| le?(item) }
    else false
    end
  end

  # O card da conversa que `account_user` pode ler, ou nil. Os cards que ele não vê (o escopo do Crm::CardPolicy) saem
  # antes de escolher o assunto atual: o de topo oculto não esconde o próximo visível. O `show?` no escolhido confere o
  # resto da regra (no EE, a chave `crm_view` da função).
  def ler(conversa, account_user)
    return unless conversa.is_a?(::Conversation) && ::Autonomia::Automacao::RegraDoFunil.chave?(account_user)

    contexto = { user: account_user.user, account: conversa.account, account_user: account_user }
    visiveis = ::Crm::CardPolicy::Scope.new(contexto, ::Crm::Card).resolve.select(:id)
    card = ::Crm::Cards::ConversationCardFinder.new(account: conversa.account).all(conversa).where(id: visiveis).first
    card if card && ::Crm::CardPolicy.new(contexto, card).show?
  end
end
