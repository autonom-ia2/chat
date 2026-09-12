# ACABAR SEM FECHAR TAMBÉM É UM DESFECHO — e ele acontece por DUAS portas (entrega 8).
#
# O motor encerra a execução em `AsyncRunJob#fail_run`: prazo esgotado, tentativas no fim, ferramenta
# ou agente indisponível. Mas quando a CORRENTE DE JOBS se rompe — o worker morto num deploy, o
# `perform_later` perdido com o Redis fora — ninguém chega lá: quem fecha a linha é o varredor
# (`ReapStaleRunsJob#close`), e até 12/09/2026 ele fechava publicando a frase de falha SEM oferecer o
# encerramento à ferramenta. O cliente lia "não consegui" com o arquivo pronto parado no handle — o
# MESMO defeito que o motor já tinha corrigido, intacto na outra porta.
#
# Por isso o encerramento mora AQUI, e não em quem encerra: uma porta nova não tem como esquecer
# metade dele. São três passos, nesta ordem:
#
#   1. ADQUIRE a marca `closed` no banco (`ausente:`): dois processos com a mesma execução e leitura
#      velha não geram dois comparativos, e quem não adquire não publica nada — quem adquiriu já
#      está publicando;
#   2. pergunta à FERRAMENTA o que ainda vale entregar (`closing_deliveries`) e publica;
#   3. publica o FECHO, escolhido pelo que o cliente tem em mãos.
#
# CADA PASSO CAI SOZINHO, E O FECHO É A ÚLTIMA COISA. A marca `closed` é adquirida ANTES de tudo — é
# ela que impede dois encerradores —, e isso tem um preço: depois dela, nenhuma passada futura
# reentra aqui. Um único `rescue` cobrindo os passos deixaria o cliente sem uma palavra, PARA SEMPRE,
# quando uma exceção caísse entre a marca e o fecho. E o risco não é teórico: o passo 2 consulta o
# banco e, na cotação, o PORTAL — o mesmo tipo de erro que produziu a linha abandonada engoliria o
# fecho junto. Entregar é cortesia que vira log quando falha; o fecho não depende do sucesso dela.
#
# E UMA ENTREGA NÃO DERRUBA AS OUTRAS: o `rescue` é POR ENTREGA, não pelo lote. Com o lote inteiro
# dentro de um tratamento só, a segunda entrega levantando apagava a primeira — `entregou` voltava
# falso e o fecho publicava a frase de falha logo depois de uma publicação bem-sucedida (Codex).
#
# QUEM PUBLICA É QUEM CHAMOU, pelo bloco: o motor publica ESPERANDO a cadeia de entrega humanizada do
# turno (e re-agenda a adiada); o varredor FORÇA (`publish!`), porque a cadeia daquele turno morreu há
# muito e esperar por ela deixaria o cliente sem desfecho para sempre.
class Autonomia::Agents::Tools::Encerramento
  # A marca do encerramento, gravada ANTES de publicar: um sinal de shutdown no meio (deploy) deixaria
  # a execução em `running`, e o retry do Sidekiq reentraria aqui.
  CLOSED_KEY = 'autonomia_closed'.freeze

  # `trabalho_novo` = esta passada pode INICIAR trabalho novo no portal para produzir uma entrega?
  # Verdadeiro no motor (uma execução por vez, num job que só faz isso); FALSO no varredor — ver
  # `ReapStaleRunsJob#encerrar`.
  def initialize(run:, native:, trabalho_novo: true, &publicador)
    @run = run
    @native = native
    @trabalho_novo = trabalho_novo
    @publicador = publicador
  end

  # -> true quando alguma entrega DO ENCERRAMENTO foi aceita (publicada, ou adiada — a adiada sai
  # sozinha pelo `AsyncPublishJob`). Elas NÃO contam em `delivered_count`, de propósito: esse contador
  # é o da entrega do TRABALHO, e é ele que diz, na janela do pedido repetido (entrega 10), que a
  # execução deu resultado.
  #
  # Não deixa `StandardError` subir: o encerramento é cortesia sobre um caminho que já deu errado, e
  # falhar aqui apagaria o `finish!` que registra o desfecho. Este `rescue` é o de fora (a aquisição
  # da marca, e o que escapar dos passos); cada passo tem o seu.
  def encerrar
    return false unless @run.merge_handle!({ CLOSED_KEY => true }, ausente: CLOSED_KEY)

    entregou = etapa('entregas') { entregar_o_que_resta }
    etapa('fecho') { publicar_fecho(entregou) }
    entregou
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento falhou slug=#{@run.slug} #{e.class}")
    false
  end

  private

  # UM PASSO, UM TRATAMENTO: o que ele levantar vira log e a sequência segue. -> o valor do passo, ou
  # false quando ele caiu — quem lê isso é o fecho, e "não sei" conta como "não entreguei", que é o
  # lado conservador.
  def etapa(nome)
    yield
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento #{nome} falhou slug=#{@run.slug} #{e.class}")
    false
  end

  # O que a ferramenta ainda tem para entregar, publicado na ordem em que ela devolveu.
  #
  # SEM AGENTE NÃO SE MONTA A FERRAMENTA, e isto não é defesa sobrando: `agente_indisponivel` é um
  # dos caminhos que chegam ao encerramento, alcançado JUSTAMENTE porque o agente sumiu.
  #
  # `count` e não `any?`: o bloco tem de rodar para TODAS as entregas. Um `any?` pararia na primeira
  # aceita e a segunda nunca sairia. (A cotação devolve no máximo uma; o contrato é `Array`.)
  def entregar_o_que_resta
    return false if ferramenta.nil?

    entregas = Array(ferramenta.closing_deliveries(handle_da_ferramenta, trabalho_novo: @trabalho_novo))
    entregas.count { |entrega| publicar_uma(entrega) }.positive?
  end

  # UMA ENTREGA POR VEZ, E O QUE ELA LEVANTAR MORRE NELA. -> ela foi aceita? O `false` do `rescue` não
  # é "recusada": é "não sei", e o fecho o lê pelo lado conservador. O que NÃO pode acontecer é a
  # entrega seguinte apagar a anterior — o cliente já está com ela na tela.
  def publicar_uma(entrega)
    resultado = publicar(entrega)
    resultado.published? || resultado.deferred?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento entrega falhou slug=#{@run.slug} #{e.class}")
    false
  end

  def publicar_fecho(entregou)
    texto = fecho(entregou)
    publicar(texto) if texto
  end

  # O FECHO VEM DEPOIS DAS ENTREGAS, e é escolhido pelo que o cliente tem em mãos. Sem NADA — nem
  # entrega do trabalho, nem entrega do encerramento —, o cliente precisa de uma palavra: a frase de
  # falha, ou a de envio incerto para quem pode ter uma cotação correndo no portal sem registro nosso
  # (entrega 5). O estado é o do BANCO, não o de uma leitura velha.
  def fecho(entregou)
    return falha_ou_incerteza unless entregou || @run.delivered_count.positive?

    parcial
  end

  def falha_ou_incerteza
    @run.envio_incerto? ? @native.uncertain_message : @native.failure_message
  end

  # A FRASE PARCIAL SÓ SAI QUANDO ELA É VERDADE, E QUEM SABE É A FERRAMENTA.
  #
  # Até aqui bastava `delivered_count.positive?`, e o contador não significa o que o fecho achava: ele
  # conta QUALQUER item aceito para publicação, inclusive a pergunta pelo dado que falta (a cotação
  # devolve `handle['pedido']` como entrega). O cliente lia que algo ficou pelo caminho — "o que
  # chegou está aqui em cima" sem nada em cima.
  #
  # São DUAS perguntas, as duas da ferramenta: houve RESULTADO (não um aviso, não uma pergunta) e
  # SOBROU algo por entregar? Sem as duas, SILÊNCIO: frase nenhuma é melhor que frase falsa.
  #
  # Sem agente não há ferramenta a quem perguntar, e sem resposta não se afirma nada: silêncio.
  def parcial
    return nil if ferramenta.nil?

    handle = handle_da_ferramenta
    return nil unless ferramenta.resultado_entregue?(handle) && ferramenta.resta_entregar?(handle)

    @native.partial_message
  end

  def publicar(entrega)
    @publicador.call(entrega)
  end

  # A ferramenta montada UMA vez para os dois passos (entregar e decidir o fecho): ela resolve
  # conexão e credencial na construção, e montá-la a cada pergunta seria trabalho repetido. Montada
  # para trabalhar FORA do turno: com a conversa da execução, com a LINHA (é pelo `delivery_token`
  # dela que a ferramenta sabe o que já foi publicado) e SEM `delivery`, de propósito — a presença
  # dele é o que diz "dentro do turno" para quem escolhe a sessão por ela. nil sem agente.
  def ferramenta
    return @ferramenta if defined?(@ferramenta)

    @ferramenta = @run.agent.blank? ? nil : montar
  end

  def montar
    @native.new(agent: @run.agent, params: @run.arguments, conversation: @run.conversation, run: @run)
  end

  # O handle da FERRAMENTA, sem as marcas do motor: ela não precisa conhecer o nosso controle. Quem as
  # define é o motor (`AsyncRunJob::MARCAS`), que é quem as escreve.
  def handle_da_ferramenta
    @run.handle.to_h.except(*::Autonomia::Agents::Tools::AsyncRunJob::MARCAS)
  end
end
