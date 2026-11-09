# Lote 4 da Automação livre (#2682): acorda o "esperar até" quando o que ele espera muda fora da conversa. A Escuta
# acorda pela conversa e pelo contato (a mensagem nova); aqui, pelo card que mudou (Crm::CardAvisaAutomacao) e pelo
# gatilho que aconteceu de novo durante a espera (Partida). Usa a mesma reserva da Escuta: marca nova, só se a execução
# continua esperando, mantendo o prazo. O erro nunca desfaz a edição do card nem a partida: vai para o log e, quando a
# execução é conhecida, para o histórico dela (`nao_acordou`), e a espera segue pelo relógio.
module Autonomia::Automacao::Despertador
  module_function

  # Roda a cada mudança lida do card: primeiro a consulta pelo índice do alvo; sem execução esperando nele (o caso comum),
  # para aí, sem ler a conta nem a flag. Só acorda a espera cuja condição lê o card (EsperaDoCard.le_o_card?).
  def card_mudou(card)
    esperando = ::Autonomia::Automacao::Execucao.where(alvo_type: 'Crm::Card', alvo_id: card.id, estado: 'esperando')
    return unless esperando.exists? && ::Autonomia::Automacao::Motor.ligado?(card.account)

    escuta.acordar_quem_espera(esperando, filtro: ::Autonomia::Automacao::EsperaDoCard.method(:le_o_card?))
  rescue StandardError => e
    escuta.registrar_erro("não acordou Crm::Card=#{card&.id}", e)
  end

  # O gatilho aconteceu de novo com a execução aberta (Partida). Só a receita com um "esperar até" que lê
  # `gatilho.repetiu` grava a hora, e só a execução esperando nesse passo é reservada (EsperaDoGatilho): a mensagem nova
  # na conversa com a execução aberta, sem essa espera, não escreve nem acorda nada.
  def gatilho_repetiu(execucao)
    espera = ::Autonomia::Automacao::EsperaDoGatilho
    return unless espera.na_receita?(execucao.versao.receita)

    execucao.update_columns(repetiu_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
    escuta.reservar(execucao) if execucao.estado == 'esperando' && espera.esperando_a_repeticao?(execucao)
  rescue StandardError => e
    nao_acordou(execucao, e)
  end

  # A rodada que acabou de gravar a espera achou a condição já cumprida (EsperaNoExecutor#reconferir_a_espera): reserva
  # o "esperar até" de novo. A ação que espera uma nova tentativa e o "esperar" de tempo seguem o relógio.
  def acordar(execucao)
    escuta.reservar(execucao) if execucao.estado == 'esperando' && escuta.esperando_condicao?(execucao)
  rescue StandardError => e
    nao_acordou(execucao, e)
  end

  # A execução que não acordou por erro (revisão do #2816): além do log, uma linha no histórico dela ("O que
  # aconteceu"), no passo em que espera, com o motivo e a classe do erro, nunca a mensagem (pode trazer dado do
  # cliente). A espera segue pelo relógio. Se nem o histórico grava, fica só o log. `passo`: a rodada que acabou de
  # gravar a espera o passa, porque a execução em memória é de antes da gravação.
  def nao_acordou(execucao, erro, passo: execucao&.cursor)
    escuta.registrar_erro("não acordou execucao=#{execucao&.id}", erro)
    return unless execucao

    ::Autonomia::Automacao::Registro.create!(account_id: execucao.account_id, automacao_id: execucao.automacao_id, execucao: execucao,
                                             passo: passo.presence || 'inicio', resultado: 'falhou', motivo: 'nao_acordou',
                                             dados: { 'erro' => erro.class.name })
  rescue StandardError => e
    escuta.registrar_erro("não registrou no histórico a falha ao acordar execucao=#{execucao&.id}", e)
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
