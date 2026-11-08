# Lote 4 da Automação livre (#2682): acorda o "esperar até" quando o que ele espera muda fora da conversa. A Escuta
# acorda pela conversa e pelo contato (a mensagem nova); aqui, pelo card que mudou (Crm::CardAvisaAutomacao) e pelo
# gatilho que aconteceu de novo durante a espera (Partida). Usa a mesma reserva da Escuta: marca nova, só se a execução
# continua esperando, mantendo o prazo. O erro é logado e nunca desfaz a edição do card nem a partida.
module Autonomia::Automacao::Despertador
  module_function

  # Roda a cada mudança lida do card: primeiro a consulta pelo índice do alvo; sem execução esperando nele (o caso comum),
  # para aí, sem ler a conta nem a flag.
  def card_mudou(card)
    esperando = ::Autonomia::Automacao::Execucao.where(alvo_type: 'Crm::Card', alvo_id: card.id, estado: 'esperando')
    return unless esperando.exists? && ::Autonomia::Automacao::Motor.ligado?(card.account)

    escuta.acordar_quem_espera(esperando)
  rescue StandardError => e
    escuta.registrar_erro("não acordou Crm::Card=#{card&.id}", e)
  end

  # Só o "esperar até": a ação que espera uma nova tentativa e o "esperar" de tempo seguem o relógio.
  def acordar(execucao)
    escuta.reservar(execucao) if execucao.estado == 'esperando' && escuta.esperando_condicao?(execucao)
  rescue StandardError => e
    escuta.registrar_erro("não acordou execucao=#{execucao&.id}", e)
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
