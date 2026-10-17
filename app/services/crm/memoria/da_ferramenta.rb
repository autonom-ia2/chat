# W5 (#1601): o RESULTADO de uma ferramenta confirma um fato; o parâmetro (o que a IA mandou, o CPF e a placa que o
# cliente disse) nunca: continua alegado, como o cliente o disse. Só execução assíncrona concluída (`done`), no card que
# estava em foco quando ela abriu (A11: a cotação do Nivus que termina com o foco no card da esposa não vai para o card
# errado). Uma linha por execução (item_ref = ferramenta:faixa): a execução nova do mesmo produto vira versão nova.
#
# Ferramentas com leitura do resultado: hoje, a cotação de seguro (o preço por seguradora).
module Crm::Memoria::DaFerramenta
  module_function

  # O card em foco na abertura da execução (Autonomia::Agents::ToolRun.open!), só com a flag.
  def card_da_abertura(account, conversation_id)
    return unless Crm::Memoria.ligada?(account)

    Crm::Assunto.funil_atual(account.conversations.find_by(id: conversation_id))&.id
  end

  def depois_de_concluir(run)
    return unless run.status == 'done' && run.card_id.present? && Crm::Memoria.ligada?(run.account)

    Crm::Memoria::DaFerramentaJob.perform_later(run.id)
  end

  def registrar!(run)
    resumo = leitura(run)
    card = Crm::Card.find_by(id: run.card_id, account_id: run.account_id)
    return if resumo.nil? || card&.contact_id.nil?

    Crm::Memoria::Gravador.gravar!(
      account_id: run.account_id, contact_id: card.contact_id, escopo: 'card', card_id: card.id, tipo: 'fato',
      chave: Crm::Memoria::Catalogo::RESULTADO_FERRAMENTA, item_ref: "#{run.slug}:#{run.faixa}", valor: resumo[:valor],
      valor_json: resumo[:valor_json], fonte: 'ferramenta_resultado', status: 'confirmado',
      prova_message_ids: [run.origin_message_id].compact, valido_desde: run.updated_at,
      gerado_por: "ferramenta:#{run.id}", idempotency_key: "ferramenta:#{run.id}"
    )
  end

  def leitura(run)
    return unless run.slug == Autonomia::Insurance::ResultadoDaCotacao.cotacao.slug

    cotacao(run)
  end

  def cotacao(run)
    resultado = Autonomia::Insurance::ResultadoDaCotacao.new(run)
    seguradoras = resultado.com_preco.map { |codigo| { nome: resultado.nome(codigo), preco: resultado.preco(codigo) } }
    return if seguradoras.empty?

    produto = run.faixa.presence || 'seguro'
    texto = "Cotação #{produto}: #{seguradoras.map { |linha| "#{linha[:nome]} #{linha[:preco]}" }.join('; ')}"
    { valor: texto, valor_json: { 'produto' => produto, 'seguradoras' => seguradoras.map(&:stringify_keys) } }
  end
end
