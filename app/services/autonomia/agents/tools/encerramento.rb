# ACABAR SEM FECHAR TAMBÉM É UM DESFECHO — e ele acontece por DUAS portas (rodada 5 da entrega 8).
#
# O motor encerra a execução em `AsyncRunJob#fail_run`: prazo esgotado, tentativas no fim, ferramenta
# ou agente indisponível. Mas quando a CORRENTE DE JOBS se rompe — o worker morto num deploy, o
# `perform_later` perdido com o Redis fora — ninguém chega lá: quem fecha a linha é o varredor
# (`ReapStaleRunsJob#close`), e até 12/09/2026 ele fechava publicando a frase de falha SEM oferecer o
# encerramento à ferramenta. O cliente lia "não consegui gerar a proposta" com o PDF pronto parado no
# handle — o MESMO defeito que a rodada 3 corrigiu no motor, intacto na outra porta.
#
# Por isso o encerramento mora AQUI, e não em quem encerra: uma porta nova não tem como esquecer
# metade dele. São quatro passos, nesta ordem:
#
#   1. ADQUIRE a marca `closed` no banco (`ausente:`): dois processos com a mesma execução e leitura
#      velha não geram dois comparativos, e quem não adquire não publica nada — quem adquiriu já
#      está publicando;
#   2. pergunta à FERRAMENTA o que ainda vale entregar (`closing_deliveries`) e publica;
#   3. deixa a ferramenta ANOTAR o que virou mensagem agora (`confirmar_publicadas`), porque depois
#      daqui não há passada nenhuma;
#   4. publica o FECHO, escolhido pelo que o cliente tem em mãos.
#
# QUEM PUBLICA É QUEM CHAMOU, pelo bloco: o motor publica ESPERANDO a cadeia de entrega humanizada do
# turno (e re-agenda a adiada); o varredor FORÇA (`publish!`), porque a cadeia daquele turno morreu há
# muito e esperar por ela deixaria o cliente sem desfecho para sempre.
class Autonomia::Agents::Tools::Encerramento
  # A marca do encerramento, gravada ANTES de publicar: um sinal de shutdown no meio (deploy) deixaria
  # a execução em `running`, e o retry do Sidekiq reentraria aqui.
  CLOSED_KEY = 'autonomia_closed'.freeze

  def initialize(run:, native:, &publicador)
    @run = run
    @native = native
    @publicador = publicador
  end

  # -> true quando alguma entrega DO ENCERRAMENTO foi aceita (publicada, ou adiada — a adiada sai
  # sozinha pelo `AsyncPublishJob`). Elas NÃO contam em `delivered_count`, de propósito: esse contador
  # é o da entrega do TRABALHO, e é ele que diz, na janela do pedido repetido (entrega 10), que a
  # execução deu resultado.
  #
  # Não deixa `StandardError` subir: o encerramento é cortesia sobre um caminho que já deu errado, e
  # falhar aqui apagaria o `finish!` que registra o desfecho.
  def encerrar
    return false unless @run.merge_handle!({ CLOSED_KEY => true }, ausente: CLOSED_KEY)

    entregou = entregar_o_que_resta
    publicar(fecho(entregou))
    entregou
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento falhou slug=#{@run.slug} #{e.class}")
    false
  end

  private

  # O que a ferramenta ainda tem para entregar, publicado na ordem em que ela devolveu — e, logo
  # depois, a chance de ela anotar o que ACABOU de virar mensagem: ninguém mais passa por aqui.
  #
  # SEM AGENTE NÃO SE MONTA A FERRAMENTA, e isto não é defesa sobrando: `agente_indisponivel` é um
  # dos caminhos que chegam ao encerramento, alcançado JUSTAMENTE porque o agente sumiu.
  def entregar_o_que_resta
    return false if @run.agent.blank?

    ferramenta = montar
    aceitas = Array(ferramenta.closing_deliveries(handle_da_ferramenta)).map { |entrega| publicar(entrega) }
    ferramenta.confirmar_publicadas(handle_da_ferramenta)
    aceitas.any? { |resultado| resultado.published? || resultado.deferred? }
  end

  # O FECHO VEM DEPOIS DAS ENTREGAS, e é escolhido pelo que o cliente tem em mãos: com algo entregue
  # (antes, ou agora no encerramento), o fecho parcial; sem nada, a frase de falha. Dizer "não
  # consegui" a quem acabou de receber preço desmente o que ele está lendo, e dizer "o que chegou está
  # aqui em cima" a quem não recebeu nada é pior ainda.
  #
  # Quem pode ter uma cotação correndo no portal sem registro nosso (entrega 5) não lê "não consegui":
  # lê que não há confirmação. O estado é o do BANCO, não o de uma leitura velha.
  def fecho(entregou)
    return @native.partial_message if entregou || @run.delivered_count.positive?

    @run.envio_incerto? ? @native.uncertain_message : @native.failure_message
  end

  def publicar(entrega)
    @publicador.call(entrega)
  end

  # A ferramenta montada para trabalhar FORA do turno: com a conversa da execução, com a LINHA (é pelo
  # `delivery_token` dela que a ferramenta sabe o que já foi publicado) e SEM `delivery`, de propósito
  # — a presença dele é o que diz "dentro do turno" para quem escolhe a sessão por ela.
  def montar
    @native.new(agent: @run.agent, params: @run.arguments, conversation: @run.conversation, run: @run)
  end

  # O handle da FERRAMENTA, sem as marcas do motor: ela não precisa conhecer o nosso controle. Quem as
  # define é o motor (`AsyncRunJob::MARCAS`), que é quem as escreve.
  def handle_da_ferramenta
    @run.handle.to_h.except(*::Autonomia::Agents::Tools::AsyncRunJob::MARCAS)
  end
end
