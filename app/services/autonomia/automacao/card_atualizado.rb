# O gatilho "card atualizado" (G27, #2661) a partir do próprio card: o Crm::CardAvisaAutomacao chama `avisar` no
# after_commit com a soma das gravações da transação (Autonomia::Automacao::MudancaDoCard.somar). É o mesmo caminho
# que acorda o "esperar até" (Despertador.card_mudou): a tela, a API, o upsert, a IA, o lote e os passos da automação
# passam por ele, porque todos gravam pelo modelo. `update_all` e `update_columns` não passam (ver o concern).
#
# Um evento por commit: a marca é o card e o `updated_at` da gravação (índice único automacao_id + evento na Partida).
# Só enfileira com automação de card atualizado ligada na conta. A ordem importa (#2750, revisão): primeiro a consulta
# pela automação ligada (uma linha, pelo índice account_id + ativa), e só quando há uma, as flags da conta. A conta sem
# automação de card atualizado não lê flag a cada edição de valor ou de campo. O erro é logado e nunca desfaz a edição.
module Autonomia::Automacao::CardAtualizado
  module_function

  def avisar(card, soma, criado:)
    mudancas = ::Autonomia::Automacao::MudancaDoCard.do_commit(soma, criado: criado)
    return if mudancas.empty?

    return unless escuta.automacoes_do_gatilho(card.account_id, ::Autonomia::Automacao::Gatilhos::ATUALIZADO).exists?

    evento = Events::Types::CRM_CARD_UPDATED
    return unless escuta.tipos_ligados(card.account, evento)

    escuta.enfileirar_evento_do_card(dados(card, mudancas), evento)
  rescue StandardError => e
    escuta.registrar_erro("card atualizado não enfileirou Crm::Card=#{card&.id}", e)
  end

  def dados(card, mudancas)
    gatilhos = ::Autonomia::Automacao::Gatilhos
    { account_id: card.account_id, card_id: card.id, changed_attributes: { 'mudancas' => mudancas },
      marca: gatilhos.marca_do_despacho(gatilhos::ATUALIZADO, card, card.updated_at) }
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
