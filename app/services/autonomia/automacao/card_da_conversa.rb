# O card que a automação de conversa lê (#2716): o assunto atual da conversa, a mesma regra do selo da lista
# (Crm::Cards::ConversationCardFinder: o aberto antes do encerrado, depois o foco mais recente). Só para ler, em todo
# lugar (decisão 19 do Rodrigo, 09/11): no "Só se", nos filtros, nos textos, copiando um campo dele, na âncora do "em
# outro registro" (`card.atributos.indicado_por`) e, no ramo dele, pela origem (`origem.card.*`, a conversa da mãe). O que
# apontaria a ação para o card (`card.*` no caminho, `card.id` no corpo) o salvar recusa (`card_da_conversa_so_le`),
# também no ramo que roda numa conversa; mexer no card é o passo "em outro registro" nos cards do contato.
#
# A única exceção (decisão 20 do Rodrigo, 10/11, "IA só anota campos", G70): o passo "extrair" preenche CAMPOS do card
# (`card.atributos.<chave>` no destino), com as regras de hoje: a chave de funis de quem salva e de quem ligou (este
# destino conta como ler o card, `le?`), a gravação pela porta da frente como quem ligou (PassoDeExtrair) e nunca o valor
# protegido (decisão 9: o destino é só campo personalizado, nunca `card.valor`). Fechar, mover, trocar o dono, webhook e
# `card.id` em caminho ou corpo continuam recusados.
# O valor protegido do card (`card.valor`) segue a regra de todo valor protegido (Valores::PROTEGIDOS, decisão 9).
#
# Ler pede a chave de funis (RegraDoFunil.chave?: `crm_manage_pipelines` ou `crm_admin`) de quem salva (controller) e de
# quem ligou (Acesso pausa sem ela), como o gatilho de card. Ao rodar, sem a chave ou sem card que ele veja (Crm::CardPolicy)
# na conversa, lê vazio; entre os cards da conversa, vale o primeiro que ele vê.
module Autonomia::Automacao::CardDaConversa
  module_function

  ID = 'card.id'.freeze
  NA_ACAO = %i[caminho corpo].freeze
  # O card lido direto (`card.`) ou, no ramo do "em outro registro", o da origem (`origem.card.`, G65).
  PREFIXOS = %w[card. origem.card.].freeze
  # G70: o destino do extrair que preenche um campo do card.
  DESTINO_DO_EXTRAIR = 'card.atributos.'.freeze

  # O caminho lê o card a partir de uma conversa?
  def do_caminho?(caminho, alvo_type) = alvo_type == 'Conversation' && caminho.to_s.split('.', 2).first == 'card'

  # Na ação (`onde`: :caminho ou :corpo), o caminho apontaria a ação para o card da conversa?
  def age?(caminho, onde, alvo_type)
    do_caminho?(caminho, alvo_type) && (onde == :caminho || caminho.to_s == ID)
  end

  # O que o salvar recusa no caminho, pelo lugar em que ele é lido (`onde`: :caminho ou :corpo da ação, :texto; nil é
  # decidir), no registro em que ele é lido (`alvo_type`: o alvo da receita, ou o do ramo do "em outro registro"; na
  # origem, o alvo da mãe): a ação que apontaria para o card da conversa. Devolve a chave da frase, ou nil.
  def problema(caminho, onde, alvo_type)
    :card_da_conversa_so_le if NA_ACAO.include?(onde) && age?(caminho, onde, alvo_type)
  end

  # Algum `$valor` lê o card (`card.*` ou `origem.card.*`)? Anda pelo trecho inteiro (a receita, ou o ramo de um passo:
  # gatilho, filtros, condições, textos, caminhos e corpos).
  def le?(trecho)
    case trecho
    when Hash then trecho.any? { |chave, valor| no_par?(trecho, chave, valor) }
    when Array then trecho.any? { |item| le?(item) }
    else false
    end
  end

  # O par do Hash lê o card: o `$valor` dele, o destino do extrair no card (G70) ou o que vem dentro.
  def no_par?(trecho, chave, valor) = (chave.to_s == '$valor' && do_card?(valor)) || anota_campo?(trecho, chave) || le?(valor)

  def do_card?(caminho) = PREFIXOS.any? { |prefixo| caminho.to_s.start_with?(prefixo) }

  # G70: o campo do extrair (`{ chave, descricao, destino }`) que grava no card. Mexe no card: pede a mesma chave de funis.
  def anota_campo?(campo, chave) = chave.to_s == 'destino' && campo['descricao'] && destino_do_card?(campo[chave])

  def destino_do_card?(destino) = destino.to_s.start_with?(DESTINO_DO_EXTRAIR)

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
