# Tema 14 (#1434) — o que muda no ciclo do `Specialists::Runner` quando o vínculo aponta para OUTRO agente (o ajudante).
# A Cotação não passa por aqui: sem ajudante, o Runner segue com as constantes dele.
#
# - etiqueta de consumo própria (`agente_ajudante`), espera de 90 s por chamada e prazo igual ao que resta da resposta
#   do principal (no máximo 5 min), para uma consulta que começa perto do fim não esticar o turno. Sem `Timeout`: o
#   relógio é o do laço e o do HTTP;
# - a base do ajudante antes do pedido. Só os erros esperados da busca (banco do pgvector, embedding) deixam o ajudante
#   seguir sem ela, marcado em `base_falhou?`; o inesperado sobe (e o `call` do Runner o registra como falha);
# - as ferramentas do ajudante rodam sem o contexto de entrega. A assíncrona nem roda: ela entregaria ao cliente. A
#   conversa vai só para o REGISTRO da recusa e para o `Idempotency-Key` da HTTP (#1430: refazer o turno manda a mesma
#   chave); a ferramenta nunca a recebe.
class Autonomia::Agents::Specialists::LacoDoAjudante
  def initialize(vinculo:, delivery:, prazo: nil)
    @vinculo = vinculo
    @delivery = delivery
    @prazo = prazo
  end

  def ajustes
    { feature: ::Autonomia::Agents::Specialists::Ajudante::FEATURE,
      timeout: ::Autonomia::Agents::Ajudantes::SEGUNDOS_POR_CHAMADA,
      max_segundos: @prazo || ::Autonomia::Agents::Ajudantes::PRAZO_DA_CONSULTA }
  end

  def base(pedido)
    ::Autonomia::Agents::Specialists::Ajudante.base(@vinculo, pedido)
  rescue ::Autonomia::Agents::Retriever::RetrievalError, ::Autonomia::Agents::EmbeddingService::EmbeddingError => e
    Rails.logger.warn("[autonomia][ajudante] base indisponivel vinculo=#{@vinculo.id} #{e.class}")
    @base_falhou = true
    []
  end

  def base_falhou?
    @base_falhou == true
  end

  def executar(tool, call)
    return recusar_assincrona(tool) if tool.async?

    tool.execute(call, delivery: nil, turno: @delivery)
  end

  private

  def recusar_assincrona(tool)
    ::Autonomia::Agents::Tools::Recusa.para_modelo('ajudante_sem_entrega', slug: tool.slug, delivery: @delivery, agente: @vinculo.agent)
  end
end
