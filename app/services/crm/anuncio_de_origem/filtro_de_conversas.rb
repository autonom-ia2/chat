# O filtro avançado de Conversas por campanha (`campaign_source_ids`, contains/does_not_contain; #2271), com a regra do
# filtro do CRM: para quem não vê o anúncio de origem, os ids de anúncio saem da condição e a divulgação continua
# filtrando; sobrando só ids de anúncio, a condição é ignorada: vale como verdadeira (ver `simplifica`). Só fica o id
# que existe na conta e nunca foi anúncio (Crm::AnuncioDeOrigem::Ids.sem_anuncio), sempre como token exato (`"id"`, o
# mesmo formato do picker): um pedaço de id digitado à mão não sonda o id do anúncio.
#
# `is_present`/`is_not_present` ficam como estão: dizem só se a conversa veio de alguma campanha ou anúncio, e quem não vê
# o anúncio já vê em cada conversa que ela veio de anúncio (só não vê qual).
#
# Quem lê vem de quem chama, explícito: a lista lê Current.user e Current.account_user (não o `current_user` que o
# controller passa ao FilterService); a contagem de não lidas por filtro salvo, o dono do filtro. Sem limite de ids.
#
#   Crm::AnuncioDeOrigem::FiltroDeConversas.payload(payload, user:, account_user:, account:) -> o payload para quem lê
module Crm::AnuncioDeOrigem::FiltroDeConversas
  CHAVE = 'campaign_source_ids'.freeze
  OPERADORES = %w[contains does_not_contain].freeze
  ASPAS = '"'.freeze
  OU = 'or'.freeze

  module_function

  def payload(payload, user:, account_user:, account:)
    return payload unless por_campanha_em?(payload)
    return payload if Crm::AnuncioDeOrigem.ve_no_contexto?(user, account_user)

    simplifica(grupos_de(condicoes_de(payload)), account)
  end

  # O FilterService#query_builder emenda as condições numa string SQL sem parênteses: vale a precedência do SQL, AND liga
  # antes de OR. `A(and) B(or) C` é `(A AND B) OR C`; `A(or) B(and) C` é `A OR (B AND C)`. Por isso as condições se
  # separam em grupos ligados por OR, e dentro de cada grupo vale AND.
  def grupos_de(condicoes)
    condicoes.slice_after { |condicao| condicao[:query_operator].to_s.casecmp?(OU) }.to_a
  end

  # A condição ignorada vale como verdadeira. Num grupo (AND), ela some. O grupo que só tinha condições ignoradas vira
  # verdadeiro, e o OR com verdadeiro é tudo: o filtro sai sem condição nenhuma (lista tudo, como a condição sozinha).
  def simplifica(grupos, account)
    restantes = grupos.map do |grupo|
      grupo.filter_map { |condicao| por_campanha?(condicao) ? sem_anuncio(condicao, account) : condicao }
    end
    return [] if restantes.any?(&:empty?)

    remonta(grupos, restantes)
  end

  # Dentro do grupo, cada condição fica com o operador dela (AND). A última de cada grupo liga ao próximo com o OR do
  # grupo original; a última de todas fica sem operador (FilterService#validate_query_operator).
  def remonta(grupos, restantes)
    restantes.each_with_index.flat_map do |grupo, indice|
      ultima = grupo.last
      fim = indice == restantes.size - 1 ? ultima.except(:query_operator) : ultima.merge(query_operator: grupos[indice].last[:query_operator])
      grupo[0...-1] + [fim]
    end
  end

  # O payload tem condição por campanha? (A contagem de não lidas só procura o dono do filtro quando tem.)
  def por_campanha_em?(payload)
    condicoes_de(payload).any? { |condicao| por_campanha?(condicao) }
  end

  def condicoes_de(payload) = Array(payload).map { |condicao| condicao.to_h.with_indifferent_access }

  def por_campanha?(condicao)
    condicao[:attribute_key] == CHAVE && OPERADORES.include?(condicao[:filter_operator])
  end

  def sem_anuncio(condicao, account)
    ids = Array(condicao[:values]).map { |valor| valor.to_s.strip.delete_prefix(ASPAS).delete_suffix(ASPAS) }
    restantes = Crm::AnuncioDeOrigem::Ids.sem_anuncio(account, ids)
    return if restantes.empty?

    condicao.merge(values: restantes.map { |id| "#{ASPAS}#{id}#{ASPAS}" })
  end
end
