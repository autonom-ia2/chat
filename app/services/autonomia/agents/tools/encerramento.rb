# ACABAR SEM FECHAR TAMBÉM É UM DESFECHO — e ele acontece por DUAS portas (entrega 8).
#
# O motor encerra a execução em `AsyncRunJob#fail_run`: prazo esgotado, tentativas no fim, ferramenta
# ou agente indisponível. Mas quando a CORRENTE DE JOBS se rompe — o worker morto num deploy, o
# `perform_later` perdido com o Redis fora — ninguém chega lá: quem fecha a linha é o varredor
# (`ReapStaleRunsJob#close`), e até 12/09/2026 ele fechava publicando a frase de falha SEM oferecer o
# encerramento à ferramenta: nem o que a ferramenta ainda tinha pronto, nem um fecho escolhido pelo
# que o cliente tem em mãos — quem já havia recebido preço lia "não consegui". O MESMO defeito que o
# motor já tinha corrigido, intacto na outra porta.
#
# O QUE MUDA DE FATO NO VARREDOR HOJE É A FRASE. Ele passa a oferecer o encerramento à ferramenta,
# mas com `trabalho_novo: false` — e a ÚNICA ferramenta assíncrona de hoje, a cotação, não tem nada
# pronto para entregar sem chamar o portal: `closing_deliveries` devolve `[]` ali, sempre. O caminho
# da entrega existe para a ferramenta que guarda um arquivo já gerado (é o desenho de que a 8b
# precisa), e não para `cotar_seguro`, que ganha desta porta só o fecho honesto.
#
# Por isso o encerramento mora AQUI, e não em quem encerra: uma porta nova não tem como esquecer
# metade dele. São três passos, nesta ordem:
#
#   1. ADQUIRE a marca `closed` no banco (`ausente:`): dois processos com a mesma execução e leitura
#      velha não geram dois comparativos — quem não adquire não repete o TRABALHO;
#   2. pergunta à FERRAMENTA o que ainda vale entregar (`closing_deliveries`) e publica;
#   3. publica o FECHO, escolhido pelo que o cliente tem em mãos.
#
# CADA PASSO CAI SOZINHO, E O FECHO É A ÚLTIMA COISA. Um único `rescue` cobrindo os passos deixaria
# o cliente sem uma palavra quando uma exceção caísse entre a marca e o fecho. E o risco não é
# teórico: o passo 2 consulta o banco e, na cotação, o PORTAL — o mesmo tipo de erro que produziu a
# linha abandonada engoliria o fecho junto. Entregar é cortesia que vira log quando falha; o fecho
# não depende do sucesso dela.
#
# A MARCA IMPEDE O TRABALHO DUAS VEZES, NÃO A PALAVRA AO CLIENTE. Ela era adquirida antes de tudo e
# fazia a passada seguinte sair sem publicar nada: morto o processo entre a marca e o fecho (um
# deploy, com os 25 s de shutdown do Sidekiq — e a janela chega a um minuto quando o passo 2 chama o
# portal), nem o retry do Sidekiq nem o varredor tentavam de novo, e o cliente ficava sem resultado
# E sem desfecho, para sempre. Agora o passo 3 é IDEMPOTENTE como os outros: ele pergunta à conversa
# se o fecho desta execução já está lá (`Tools::EntregaPublicada`, pela identidade de cada frase
# possível) e só publica o que falta; a dedupe por token do publicador é a segunda guarda.
#
# E UMA ENTREGA NÃO DERRUBA AS OUTRAS: o `rescue` é POR ENTREGA, não pelo lote. Com o lote inteiro
# dentro de um tratamento só, a segunda entrega levantando apagava a primeira — `entregou` voltava
# falso e o fecho publicava a frase de falha logo depois de uma publicação bem-sucedida (Codex).
#
# QUEM PUBLICA É QUEM CHAMOU, pelo bloco: o motor publica ESPERANDO a cadeia de entrega humanizada do
# turno (e re-agenda a adiada); o varredor FORÇA (`publish!`), porque a cadeia daquele turno morreu há
# muito e esperar por ela deixaria o cliente sem desfecho para sempre.
class Autonomia::Agents::Tools::Encerramento
  # A marca do TRABALHO do encerramento, adquirida antes dele: um sinal de shutdown no meio (deploy)
  # deixaria a execução em `running`, o retry do Sidekiq reentraria aqui, e a ferramenta geraria de
  # novo o que ela já tinha gerado. Ela NÃO guarda o fecho — ver o cabeçalho.
  CLOSED_KEY = 'autonomia_closed'.freeze

  # As frases que o fecho pode dizer. É por elas que se pergunta à conversa se o fecho desta
  # execução já saiu: a identidade de uma entrega publicada é derivada do CONTEÚDO
  # (`ToolRun#delivery_token`), então a pergunta "já houve fecho?" é a pergunta por cada uma. São
  # três textos de CLASSE, e é por isso que ela se faz mesmo quando a ferramenta não pôde ser
  # montada.
  FRASES_DE_FECHO = %i[failure_message uncertain_message partial_message].freeze

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
  #
  # QUEM NÃO ADQUIRE A MARCA NÃO REFAZ O TRABALHO — mas ainda fecha. É a passada que chega depois de
  # um processo morto entre a marca e o fecho: a linha ficou `running`, o retry do Sidekiq ou o
  # varredor voltam aqui, e o cliente ainda não recebeu palavra nenhuma. O passo 3 sabe distinguir
  # (`fecho_publicado?`), então repetir a passada não duplica.
  def encerrar
    entregou = adquiriu_o_trabalho? && etapa('entregas') { entregar_o_que_resta }
    etapa('fecho') { publicar_fecho(entregou) }
    entregou
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento falhou slug=#{@run.slug} #{e.class}")
    false
  end

  private

  # A aquisição da marca, no banco e só se ela ainda não estiver lá. -> esta passada é a dona do
  # trabalho?
  def adquiriu_o_trabalho?
    @run.merge_handle!({ CLOSED_KEY => true }, ausente: CLOSED_KEY)
  end

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
  #
  # O ACEITE FICA REGISTRADO na linha (`Tools::EntregaAceita`), como no motor: é por ele que uma
  # segunda passada — e a própria ferramenta, logo abaixo, ao decidir o fecho — sabe que esta
  # entrega já foi assumida pelo publicador, mesmo quando ela ainda não virou mensagem.
  def publicar_uma(entrega)
    resultado = ::Autonomia::Agents::Tools::EntregaAceita.registrar(@run, entrega, publicar(entrega))
    resultado.aceita?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento entrega falhou slug=#{@run.slug} #{e.class}")
    false
  end

  # O FECHO SAI UMA VEZ, E A PERGUNTA É PELA MENSAGEM. Duas passadas sobre a mesma linha (o retry
  # do Sidekiq, o varredor cruzando com o motor, a passada que veio depois de um processo morto no
  # meio) podem escolher frases DIFERENTES — a segunda não refaz as entregas, então lê `entregou`
  # como falso —, e aí a dedupe por token do publicador não salvaria: seriam dois textos, duas
  # mensagens, uma contradizendo a outra. Por isso se pergunta antes, e por TODAS as frases.
  def publicar_fecho(entregou)
    return if fecho_publicado?

    texto = fecho(entregou)
    publicar(texto) if texto
  end

  # Alguma das frases de fecho DESTA execução já está na conversa?
  def fecho_publicado?
    conversa = @run.conversation
    return false if conversa.blank?

    FRASES_DE_FECHO.any? do |frase|
      token = ::Autonomia::Agents::Tools::EntregaPublicada.token_de(@run, @native.public_send(frase))
      ::Autonomia::Agents::Tools::EntregaPublicada.publicada?(conversa, token)
    end
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
  # SEM AGENTE NÃO HÁ FERRAMENTA A QUEM PERGUNTAR, E AÍ É SILÊNCIO — decisão declarada, e mudança
  # em relação à `main`, que publicava a frase parcial por `delivered_count.positive?` sozinho.
  # `partial_message` é de CLASSE justamente para sair sem instância (entrega 4), e continua sendo:
  # o que mudou é que agora ela precisa ser VERDADE, e quem sabe se houve resultado e se sobrou algo
  # é a ferramenta. Afirmar sem poder conferir é o defeito que esta entrega corrige.
  #
  # E o caminho é o `agente_indisponivel` (`AsyncRunJob#stop?`: a linha existe, o agente não): com o
  # agente apagado, `agent_inboxes` cai com ele (`dependent: :destroy`), então
  # `Operate.authorized_agent_inbox` não acha vínculo e o publicador recusa TUDO (`blocked`) — a
  # frase da `main` também não chegava ao cliente. O que se perde aqui é uma publicação que já era
  # recusada; o que se ganha é não afirmar no escuro. As frases de falha e de incerteza continuam
  # sendo tentadas, porque elas não afirmam nada sobre o que chegou.
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
  # para trabalhar FORA do turno: com a LINHA (é pelo `delivery_token` dela que a ferramenta monta a
  # identidade de cada entrega, e é nela que está o registro do aceite) e SEM `delivery`, de
  # propósito — a presença dele é o que diz "dentro do turno" para quem escolhe a sessão por ela.
  # nil sem agente.
  #
  # A MESMA INSTÂNCIA atravessa os dois passos, e é isso que faz a lista do aceite chegar atualizada
  # ao fecho: `publicar_uma` grava nela pela LINHA, e `registrar_entrega_aceita!` recarrega o objeto
  # que a ferramenta tem em mãos.
  def ferramenta
    return @ferramenta if defined?(@ferramenta)

    @ferramenta = @run.agent.blank? ? nil : montar
  end

  def montar
    @native.new(agent: @run.agent, params: @run.arguments, run: @run)
  end

  # O handle da FERRAMENTA, sem as marcas do motor: ela não precisa conhecer o nosso controle. Quem as
  # define é o motor (`AsyncRunJob::MARCAS`), que é quem as escreve.
  def handle_da_ferramenta
    @run.handle.to_h.except(*::Autonomia::Agents::Tools::AsyncRunJob::MARCAS)
  end
end
