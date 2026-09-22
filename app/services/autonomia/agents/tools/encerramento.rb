# ACABAR SEM FECHAR TAMBÉM É UM DESFECHO — e ele acontece por DUAS portas (entrega 8).
#
# O motor encerra a execução em `AsyncRunJob#fail_run`: prazo esgotado, tentativas no fim, ferramenta
# ou agente indisponível. Mas quando a CORRENTE DE JOBS se rompe — o worker morto num deploy, o
# `perform_later` perdido com o Redis fora — ninguém chega lá: quem fecha a linha é o varredor
# (`ReapStaleRunsJob#close`). As duas portas passam por aqui, para uma porta nova não ter como esquecer
# metade do encerramento.
#
# O DESFECHO É UM EVENTO, NÃO UMA FRASE (PR C). Até aqui este arquivo escolhia e publicava a frase de fecho —
# constante nossa ou frase do especialista. Agora ele escolhe o TIPO do desfecho e o dispara (`Tools::Evento`):
# quem fala com o cliente é a Lia, num turno de modelo acionado por ele. Frase pronta ao cliente não sai daqui.
#
# DOIS PASSOS, nesta ordem, e cada um cai sozinho:
#
#   1. ADQUIRE a marca `closed` no banco (`ausente:`) e pergunta à FERRAMENTA o que ainda vale entregar
#      (`closing_deliveries`, hoje o comparativo), e publica: dois processos com a mesma execução e leitura
#      velha não geram dois comparativos — quem não adquire não repete o TRABALHO;
#   2. dispara o EVENTO de desfecho, escolhido pelo que o cliente tem em mãos.
#
# A IDEMPOTÊNCIA DO DESFECHO É O SLOT DO EVENTO (`Tools::Evento::FECHO_KEY`), adquirido no banco: a passada que
# volta depois de um processo morto entre os dois passos, o retry do Sidekiq e o varredor cruzando com o motor
# encontram o slot tomado e não disparam de novo. Era a pergunta à conversa por cada frase possível
# (`fecho_publicado?`, pelo SHA do texto); com o texto fora daqui, ela saiu junto.
#
# QUEM PUBLICA O ARQUIVO É QUEM CHAMOU, pelo bloco: o motor publica ESPERANDO a cadeia de entrega humanizada do
# turno (e re-agenda a adiada); o varredor FORÇA (`publish!`), porque a cadeia daquele turno morreu há muito.
#
# A EXECUÇÃO QUE TERMINA EM `done` TAMBÉM PASSA POR AQUI, por `concluir`: só o evento. Se a própria consulta já
# conhece o desfecho (a recusa do envio, `Progress#evento`), é ele que sai.
class Autonomia::Agents::Tools::Encerramento
  # A marca do TRABALHO do encerramento, adquirida antes dele: um sinal de shutdown no meio (deploy)
  # deixaria a execução em `running`, o retry do Sidekiq reentraria aqui, e a ferramenta geraria de
  # novo o que ela já tinha gerado. Ela NÃO guarda o desfecho — quem guarda é o slot do evento.
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

  # -> true quando alguma entrega DO ENCERRAMENTO foi aceita (publicada, ou adiada — a adiada fica com o
  # `AsyncPublishJob`, que ainda pode recusá-la). Elas NÃO contam em `delivered_count`, de propósito: esse
  # contador é o da entrega do TRABALHO.
  #
  # Não deixa `StandardError` subir: o encerramento é cortesia sobre um caminho que já deu errado, e
  # falhar aqui apagaria o `finish!` que registra o desfecho. Este `rescue` é o de fora (a aquisição
  # da marca, e o que escapar dos passos); cada passo tem o seu.
  def encerrar
    entregou = adquiriu_o_trabalho? && etapa('entregas') { entregar_o_que_resta }
    etapa('evento') { disparar(fecho(entregou)) }
    entregou
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento falhou slug=#{@run.slug} #{e.class}")
    false
  end

  # O DESFECHO DE UMA EXECUÇÃO QUE TERMINOU (`done`), chamado por `AsyncRunJob#finish_done` antes do
  # `finish!`. Não adquire a marca `closed` e não entrega nada: só dispara o evento — o que a consulta já
  # trouxe (`evento`, a recusa do envio), ou o que `conclusao` escolher. -> nil.
  #
  # AO CONTRÁRIO DE `encerrar`, O QUE LEVANTA AQUI SOBE. No motor, a exceção chega a
  # `AsyncRunJob#advance`, que trata a passada como falha e a tenta de novo (`retry_or_fail`) sem
  # chegar ao `finish!`. Engolir aqui fecharia a linha em `done` sem desfecho.
  def concluir(evento = nil)
    disparar(evento.presence || conclusao)
    nil
  end

  private

  # A aquisição da marca, no banco e só se ela ainda não estiver lá. -> esta passada é a dona do
  # trabalho?
  def adquiriu_o_trabalho?
    @run.merge_handle!({ CLOSED_KEY => true }, ausente: CLOSED_KEY)
  end

  # UM PASSO, UM TRATAMENTO: o que ele levantar vira log e a sequência segue. -> o valor do passo, ou
  # false quando ele caiu — quem lê isso é o desfecho, e "não sei" conta como "não entreguei", que é o
  # lado conservador.
  def etapa(nome)
    yield
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento #{nome} falhou slug=#{@run.slug} #{e.class}")
    false
  end

  # O arquivo que ESTE encerramento adiou vai junto (`depois_de`): o turno do evento espera ele virar mensagem
  # mesmo quando a escrita do aceite dele falhou e a lista do aceite não o mostra.
  def disparar(tipo)
    ::Autonomia::Agents::Tools::Evento.disparar(@run, tipo, depois_de: [@adiada].compact) if tipo
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
  # é "recusada": é "não sei", e o desfecho o lê pelo lado conservador.
  #
  # O ACEITE FICA REGISTRADO na linha (`Tools::EntregaAceita`), como no motor: é por ele que uma segunda
  # passada — e a ferramenta, logo abaixo, ao decidir o desfecho — sabe que esta entrega já foi assumida pelo
  # publicador, e é por ele que o turno do evento espera o arquivo virar mensagem antes de falar.
  def publicar_uma(entrega)
    resultado = ::Autonomia::Agents::Tools::EntregaAceita.registrar(@run, entrega, @publicador.call(entrega))
    @adiada = ::Autonomia::Agents::Tools::EntregaPublicada.token_de(@run, entrega) if resultado.deferred?
    resultado.aceita?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento entrega falhou slug=#{@run.slug} #{e.class}")
    false
  end

  # O DESFECHO VEM DEPOIS DAS ENTREGAS, e é escolhido pelo que o cliente tem em mãos. O estado é o do BANCO, não
  # o de uma leitura velha.
  #   - resultado guardado e nenhum entregue: `valores_guardados` (a Lia diz que ele pode pedir aqui);
  #   - nada entregue e nenhum resultado: `falhou`, ou `incerta` para quem pode ter uma cotação correndo no
  #     portal sem registro nosso (entrega 5);
  #   - resultado entregue: `encerrada_por_prazo` quando sobrou algo por entregar, `concluida` quando não.
  #
  # O RESULTADO JÁ ENTREGUE CONTA MESMO COM O CONTADOR ZERADO (o comparativo com o envio pendente não foi contado
  # pelo publicador), e a entrega que ESTE encerramento acabou de ter aceita (`entregou`) também conta: com a
  # escrita do aceite falhando, a lista do aceite não a mostra.
  def fecho(entregou)
    return 'valores_guardados' if !entregou && valores_a_pedir?
    return falha_ou_incerteza unless entregou || @run.delivered_count.positive? || resultado_entregue?

    com_resultado(entregou)
  end

  def falha_ou_incerteza
    @run.envio_incerto? ? 'incerta' : 'falhou'
  end

  # O DESFECHO DE QUEM TERMINOU (`concluir`). Resultado guardado que não chegou: `valores_guardados`. Resultado
  # confirmado pela ferramenta (`resultado_entregue?`): `concluida` — desde a PR C o comparativo sai sem legenda,
  # e é a Lia quem fala depois dele. Contador zero: `falhou`. Entrega aceita que não é resultado, ou execução sem
  # agente: nenhum evento.
  def conclusao
    return 'valores_guardados' if valores_a_pedir?
    return 'concluida' if resultado_entregue?
    return 'falhou' if @run.delivered_count.zero?

    nil
  end

  # O DESFECHO DE QUEM TEM RESULTADO SÓ É AFIRMADO QUANDO É VERDADE, E QUEM SABE É A FERRAMENTA: houve RESULTADO
  # (não um aviso, não uma pergunta) e SOBROU algo por entregar? Sem ferramenta (agente apagado) não há a quem
  # perguntar, e aí não há evento: afirmar no escuro é o defeito que a entrega 8 corrigiu.
  #
  # `entregou` é a entrega do encerramento aceita agora (na cotação, o comparativo): é resultado mesmo quando a
  # escrita do aceite dela falhou.
  def com_resultado(entregou)
    return nil if ferramenta.nil?

    handle = handle_da_ferramenta
    return nil unless entregou || ferramenta.resultado_entregue?(handle)

    ferramenta.resta_entregar?(handle) ? 'encerrada_por_prazo' : 'concluida'
  end

  # A ferramenta confirma que o cliente tem resultado? Sem agente não há ferramenta, e a resposta é não.
  def resultado_entregue?
    ferramenta.present? && ferramenta.resultado_entregue?(handle_da_ferramenta)
  end

  # A ferramenta guardou resultado que não chegou ao cliente? Sem agente não há ferramenta, e a resposta é não.
  def valores_a_pedir?
    ferramenta.present? && ferramenta.resultado_a_pedir?(handle_da_ferramenta)
  end

  # A ferramenta montada UMA vez para os dois passos (entregar e decidir o desfecho): ela resolve
  # conexão e credencial na construção. Montada para trabalhar FORA do turno: com a LINHA (é pelo
  # `delivery_token` dela que a ferramenta monta a identidade de cada entrega, e é nela que está o registro
  # do aceite) e SEM `delivery`, de propósito. nil sem agente.
  #
  # A MESMA INSTÂNCIA atravessa os dois passos, e é isso que faz a lista do aceite chegar atualizada
  # ao desfecho: `publicar_uma` grava nela pela LINHA, e `registrar_entrega_aceita!` recarrega o objeto
  # que a ferramenta tem em mãos.
  def ferramenta
    return @ferramenta if defined?(@ferramenta)

    @ferramenta = @run.agent.blank? ? nil : @native.new(agent: @run.agent, params: @run.arguments, run: @run)
  end

  # O handle da FERRAMENTA, sem as marcas do motor: ela não precisa conhecer o nosso controle. Quem as
  # define é o motor (`AsyncRunJob::MARCAS`), que é quem as escreve.
  def handle_da_ferramenta
    @run.handle.to_h.except(*::Autonomia::Agents::Tools::AsyncRunJob::MARCAS)
  end
end
