# AS OUTRAS COTAÇÕES DA MESMA VIAGEM COM CARRINHO NÃO PAGO (#3266): o que `gerar_proposta_seguro_viagem` procura antes
# de comprar, além do carrinho da própria cotação (`SeguroViagem::CarrinhoAnterior`).
#
# POR QUÊ. O cliente volta outro dia e a Bia cota de novo a mesma viagem: a cotação é outra, mas o carrinho não pago da
# antiga continua com voucher "Ativo" na Universal, que recusa a compra nova ("já consta um voucher para essa viagem").
#
# QUAIS. Outras cotações DESTE agente nesta conversa, da MESMA viagem (`PropostaPaga.mesma_viagem?`: destinos, datas e
# idades), com `codigo_carrinho` guardado, sem `pago_em` e sem a marca `situacao: cancelado`. Viagem diferente não é
# lida nem cancelada. A decisão sobre cada carrinho é a do `CarrinhoAnterior.liberar!` (só o vazio cancela).
#
# A MARCA. Cancelado o carrinho de uma delas, a proposta dela ganha `situacao: cancelado` e `cancelado_na_troca_em`: a
# varredura do pagamento não a confere mais e o lembrete se cala. A marca é gravada DEPOIS da compra (saindo ou não),
# fora da transação dela: o erro da compra desfaz a transação, e o cancelamento na Universal não volta atrás.
#
# O LOCK. Essas cotações não ficam travadas durante as chamadas à Universal: quem mais escreve nelas é a conferência
# automática do pagamento e as ferramentas de pagamento, que travam a linha por pouco tempo, e um lock longo aqui as
# faria estourar a espera. A marca usa um lock próprio e curto, relendo a proposta: só marca se o carrinho ainda é o
# cancelado e não há `pago_em`. A marca que não grava (espera do lock estourada ou outro erro do banco) só vai ao log,
# por cotação, e a próxima segue: quem chamou já tem o texto da compra, que não se perde por isso, e a conferência
# automática lê "Cancelado" e grava o mesmo `situacao`. Log só com ids.
module Autonomia::Agents::Tools::Native::SeguroViagem::OutrasDaMesmaViagem
  Pagamento = Autonomia::Agents::Tools::Native::SeguroViagem::Pagamento
  PropostaPaga = Autonomia::Agents::Tools::Native::SeguroViagem::PropostaPaga

  module_function

  # -> as outras cotações da mesma viagem com carrinho em aberto, da mais velha para a mais nova.
  def com_carrinho(cotacao, agent)
    Autonomia::Agents::CotacaoDeViagem.where(conversation_id: cotacao.conversation_id, autonomia_agent_id: agent.id)
                                      .where.not(id: cotacao.id)
                                      .where("proposta->>'codigo_carrinho' IS NOT NULL")
                                      .where("COALESCE(proposta->>'pago_em', '') = ''")
                                      .where("proposta->>'situacao' IS DISTINCT FROM ?", Pagamento::CANCELADO)
                                      .order(:id).select { |outra| PropostaPaga.mesma_viagem?(outra, cotacao) }
  end

  # `canceladas`: os pares [cotação, carrinho] cancelados nesta chamada.
  def marcar_canceladas(canceladas)
    canceladas.each { |outra, carrinho| marcar(outra, carrinho) }
  end

  def marcar(outra, carrinho)
    outra.with_lock do
      proposta = outra.proposta.to_h
      if proposta['codigo_carrinho'] == carrinho && proposta['pago_em'].blank?
        marca = { 'situacao' => Pagamento::CANCELADO, 'cancelado_na_troca_em' => Time.current.iso8601 }
        outra.update!(proposta: proposta.merge(marca))
      end
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][seguro_viagem] outra_cotacao_sem_marca cotacao=#{outra.id} #{e.class}")
  end

  private_class_method :marcar
end
