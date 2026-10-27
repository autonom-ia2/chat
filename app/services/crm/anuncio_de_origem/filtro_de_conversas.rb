# O filtro avançado de Conversas por campanha (`campaign_source_ids`, contains/does_not_contain; #2271), com a regra do
# filtro do CRM: para quem não vê o anúncio de origem, os ids de anúncio saem da condição e a divulgação continua
# filtrando; sobrando só ids de anúncio, a condição é ignorada. Só fica o id que existe na conta e nunca foi anúncio
# (Crm::AnuncioDeOrigem::Ids.sem_anuncio), sempre como token exato (`"id"`, o mesmo formato do picker): um pedaço de id
# digitado à mão não sonda o id do anúncio.
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

  module_function

  def payload(payload, user:, account_user:, account:)
    return payload unless por_campanha_em?(payload)
    return payload if Crm::AnuncioDeOrigem.ve_no_contexto?(user, account_user)

    fecha(condicoes_de(payload).filter_map { |condicao| por_campanha?(condicao) ? sem_anuncio(condicao, account) : condicao })
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

  # A última condição não leva operador de junção (FilterService#validate_query_operator).
  def fecha(condicoes)
    return condicoes if condicoes.empty?

    condicoes[0...-1] + [condicoes.last.except(:query_operator)]
  end
end
