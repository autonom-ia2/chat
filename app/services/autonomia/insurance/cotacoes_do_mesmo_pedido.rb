# AS OUTRAS COTAÇÕES DO MESMO PEDIDO, e o que a pessoa já ouviu de cada uma (item 6 da auditoria de voz, 26/09/2026).
#
# Quando a pessoa pede o carro, a casa e o apartamento numa mensagem só, cada bem vira uma execução (a faixa, chat#612),
# e cada uma termina com o seu aviso. A Lia recebia cada aviso sem saber dos outros, e anunciava o segundo e o terceiro
# comparativo com a mesma forma do primeiro. Este é o fato que ela não tinha: quais cotações saíram da mesma mensagem,
# e se a notícia de cada uma já foi dada.
#
# O MESMO PEDIDO é a mesma mensagem de origem (`origin_message_id`), a chave que o `ToolRun` já usa para separar pedido
# novo de retry. Supersedida, descartada e bloqueada ficam de fora: foram substituídas ou nunca viraram trabalho. JÁ CONTADA é o
# desfecho dela ter mensagem na conversa (`Tools::Evento#publicado?`), a mesma pergunta que a idempotência do evento faz.
# A que terminou e ainda não foi contada fica só como "terminou": nem todo desfecho tem aviso a caminho, e o fato não
# promete mensagem (revisão adversarial de 26/09/2026).
module Autonomia::Insurance::CotacoesDoMesmoPedido
  FORA = %w[superseded discarded blocked].freeze
  CONTADA = 'já contada à pessoa'.freeze
  # A DIREÇÃO VAI JUNTO DO FATO (avaliação paga de 26/09/2026): com a §14 dizendo para não repetir a forma, as três
  # falas seguidas abriram igual ("O comparativo do..."). A regra mais perto da ação vence, então ela vem aqui.
  OUTRA_ABERTURA = 'A notícia de outra cotação deste pedido já foi dada: abra esta mensagem de outro jeito.'.freeze

  module_function

  # -> a frase de fatos sobre as outras cotações do pedido desta execução, ou nil quando não há outra.
  # NUNCA LEVANTA: os fatos do aviso saem inteiros ou não saem (`Tools::Evento#fatos`), e uma falha aqui levaria junto
  # o que a Lia não pode dizer (`Eventos::SEM_QUEM_FICOU_DE_FORA`). Sem esta frase, o aviso sai como era antes dela.
  def fatos(run)
    outras = outras(run)
    return nil if outras.empty?

    situacoes = outras.map { |outra| situacao(outra) }
    itens = outras.zip(situacoes).map { |outra, sit| "#{::Autonomia::Insurance::Faixa.descricao(outra)}, #{sit}" }
    ["Outras cotações pedidas na mesma mensagem da pessoa: #{itens.join('; ')}.",
     (OUTRA_ABERTURA if situacoes.include?(CONTADA))].compact.join(' ')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] cotacoes do mesmo pedido indisponiveis run=#{run&.id} #{e.class}")
    nil
  end

  def outras(run)
    return [] if run.origin_message_id.blank? || run.conversation_id.blank?

    ::Autonomia::Agents::ToolRun.for_conversation(run.conversation_id)
                                .where(slug: run.slug, origin_message_id: run.origin_message_id)
                                .where.not(id: run.id).where.not(status: FORA).order(:created_at, :id).to_a
  end

  def situacao(outra)
    return 'ainda correndo' if ::Autonomia::Agents::ToolRun::ACTIVE_STATUSES.include?(outra.status)

    contada?(outra) ? CONTADA : 'terminou'
  end

  def contada?(outra)
    tipo = outra.handle.to_h[::Autonomia::Agents::Tools::Evento::FECHO_KEY]
    tipo.present? && ::Autonomia::Agents::Tools::Evento.new(run: outra, tipo: tipo).publicado?(outra.conversation)
  end
end
