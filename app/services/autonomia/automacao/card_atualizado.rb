# O gatilho "card atualizado" (G27, #2661) a partir do próprio card: o Crm::CardAvisaAutomacao chama `avisar` no
# after_commit com a soma das gravações da transação (Autonomia::Automacao::MudancaDoCard.somar). É o mesmo caminho
# que acorda o "esperar até" (Despertador.card_mudou): a tela, a API, o upsert, a IA, o lote e os passos da automação
# passam por ele, porque todos gravam pelo modelo. `update_all` e `update_columns` não passam (ver o concern).
#
# Um evento por commit: a marca é o card e o `updated_at` da gravação (índice único automacao_id + evento na Partida).
# Só enfileira com automação de card atualizado ligada na conta. A ordem importa (#2750, revisão): primeiro a consulta
# pela mudança escolhida em cada automação ligada (pelo índice account_id + ativa), e só quando há uma, as flags da
# conta. A conta sem automação de card atualizado não lê flag a cada edição de valor ou de campo. O valor de venda não
# vai no evento: a mesma consulta traz as condições no valor, conferidas aqui (MudancaDoCard.conferir_valor). O erro é
# logado e nunca desfaz a edição.
module Autonomia::Automacao::CardAtualizado
  module_function

  def avisar(card, soma, criado:)
    mudancas = ::Autonomia::Automacao::MudancaDoCard.do_commit(soma, criado: criado)
    return if mudancas.empty?

    gatilhos = mudancas_escolhidas(card.account_id)
    return if gatilhos.empty?

    evento = Events::Types::CRM_CARD_UPDATED
    return unless escuta.tipos_ligados(card.account, evento)

    escuta.enfileirar_evento_do_card(dados(card, ::Autonomia::Automacao::MudancaDoCard.conferir_valor(mudancas, gatilhos)), evento)
  rescue StandardError => e
    escuta.registrar_erro("card atualizado não enfileirou Crm::Card=#{card&.id}", e)
  end

  # A `mudanca` do gatilho de cada automação de card atualizado ligada na conta, numa consulta. A condição no valor de
  # quem ligou sem ver os valores (#2597) fica de fora: nem a faixa dela vai no evento.
  def mudancas_escolhidas(account_id)
    escuta.automacoes_do_gatilho(account_id, ::Autonomia::Automacao::Gatilhos::ATUALIZADO)
          .pluck(Arel.sql("autonomia_automacao_versoes.receita -> 'gatilho' -> 'mudanca'"), 'autonomia_automacoes.ligada_por_id')
          .filter_map { |mudanca, quem| mudanca if ::Autonomia::Automacao::MudancaDoCard.le_a_mudanca?(mudanca, account_id, quem) }
  end

  def dados(card, mudancas)
    gatilhos = ::Autonomia::Automacao::Gatilhos
    { account_id: card.account_id, card_id: card.id, changed_attributes: { 'mudancas' => mudancas },
      marca: gatilhos.marca_do_despacho(gatilhos::ATUALIZADO, card, card.updated_at) }
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
