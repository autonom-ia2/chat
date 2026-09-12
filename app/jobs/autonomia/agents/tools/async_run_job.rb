# MOTOR da ferramenta assíncrona (#313): submete, consulta de tempos em tempos, publica.
#
# NÃO SEGURA WORKER. Cada execução é curta (uma submissão ou uma consulta) e se re-agenda com
# `set(wait:)` até acabar — mesmo desenho de `EmailCampaigns::Ai::PollJob`, que já roda em
# produção. Dormir os ~90s da cotação dentro do job seria pior do que parece: o Sidekiq desta
# instalação tem `:timeout: 25` de shutdown, então TODO deploy mataria a espera no meio, e o
# `:max_retries: 3` reexecutaria o job do zero — o que aqui significa cotar de novo na
# seguradora, com custo e duplicidade no portal do corretor.
#
# O `advance` CAPTURA o `StandardError` do trabalho e o encaminha para nova tentativa ou desfecho.
# Deixar o Sidekiq reexecutar refaria o `start`; aqui uma falha ou é uma nova tentativa controlada
# (dentro do prazo) ou é o fim com mensagem honesta ao cliente. Silêncio nunca é opção: o cliente
# está esperando. O que está fora do `advance` (as guardas de `stop?`, o aviso de espera) e uma falha
# dentro do próprio tratamento (`retry_or_fail`) podem propagar; e o sinal de desligamento
# (`Sidekiq::Shutdown`, um `Interrupt`) passa, de propósito — ver `tentar_start`.
class Autonomia::Agents::Tools::AsyncRunJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig
  ToolRun = ::Autonomia::Agents::ToolRun

  # Marca nossa, gravada no handle junto com o que a ferramenta devolveu. É ela que diz "já
  # submeti" — não o conteúdo do handle. Sem isso, uma ferramenta que devolvesse nil ou {} faria a
  # passada seguinte chamar `start` DE NOVO, até 60 vezes: 60 cotações reais no portal.
  # O nome mora no modelo desde a entrega 5: o varredor e o desfecho leem a marca para saber se um
  # envio ficou incerto.
  SUBMITTED_KEY = ToolRun::SUBMITTED_KEY
  # MESMA IDEIA DO `SUBMITTED_KEY`, para o outro extremo da execução. O encerramento publica e só
  # DEPOIS `finish!` registra o desfecho: um sinal de shutdown no meio (deploy) deixaria a execução
  # em `running`, e o retry do Sidekiq reentraria. A marca é gravada ANTES de publicar.
  #
  # HONESTIDADE SOBRE O QUE ESTÁ PROVADO: não consegui reproduzir essa reentrada em teste — forçar
  # o status de volta para `running` não faz o job reentrar no encerramento. O spec trava que a
  # marca é gravada (pega a remoção acidental); a proteção contra o retry é raciocínio, como era a
  # do `SUBMITTED_KEY` quando ele nasceu.
  #
  # Desde a entrega 8 quem a DEFINE é `Tools::Encerramento`, dono do encerramento inteiro
  # (o varredor fecha pelo mesmo caminho). O nome continua aqui porque ela é uma das MARCAS do motor.
  CLOSED_KEY = ::Autonomia::Agents::Tools::Encerramento::CLOSED_KEY

  # A LINHA MUDOU DE DONO no meio da passada: um pedido novo a supersedeu, ou outro processo com a
  # mesma execução (o Sidekiq re-enfileira o job no hard shutdown, e o antigo pode estar vivo noutro
  # host por alguns milissegundos) anotou a intenção seguinte. Esta passada PARA — sem chamar o
  # portal, sem gravar, sem se reagendar: quem tem a linha agora é quem decide. Levantada pelas
  # escritas com compare-and-set de `submeter`.
  MudouDeDono = Class.new(StandardError)

  def perform(run_id, attempt = 0)
    run = ToolRun.find_by(id: run_id)
    return if run.blank? || !run.running?

    native = ::Autonomia::Agents::Tools::Registry.find(run.slug)
    return if stop?(run, native, attempt.to_i)

    notify_start(run, native)
    advance(run, native, attempt.to_i)
  end

  private

  # Motivos para NÃO dar mais um passo. Verificados antes de qualquer chamada ao portal — cada passo
  # é uma cotação de verdade, com custo e registro na seguradora.
  def stop?(run, native, attempt)
    if native.blank?
      fail_run(run, nil, 'ferramenta_indisponivel')
    elsif run.agent.blank?
      fail_run(run, native, 'agente_indisponivel')
    # O operador puxou o freio (kill-switch da conta, agente desligado, conversa fora da allowlist
    # de piloto) DEPOIS do disparo. Sem esta guarda o job seguiria cotando por até 60 tentativas
    # contra a vontade de quem desligou.
    elsif ::Autonomia::Agents::Operate.authorized_agent_inbox(run.conversation).blank?
      block_run(run)
    elsif run.expired? || attempt >= AsyncConfig::MAX_ATTEMPTS
      fail_run(run, native, 'prazo_esgotado')
    else
      return false
    end
    true
  end

  # Aviso de espera escrito pelo CÓDIGO, publicado só quando o turno ficou em silêncio (o
  # modelo emitiu o sinal de silêncio, a IA falhou, ou a porta de engajamento fechou). Sem
  # isto, o cliente que se despede na mesma mensagem em que pede a cotação recebe zero
  # confirmação e, um minuto depois, uma cotação caindo do nada.
  def notify_start(run, native)
    return unless run.notify_customer && run.sequence.zero?

    publish(run, native.waiting_message)
  end

  # Submete (primeira passada) ou consulta (demais). A ferramenta é instanciada a cada
  # execução: ela resolve conexão e credencial sozinha, e nada disso trafega pelo Redis.
  def advance(run, native, attempt)
    tool = ferramenta(run, native)
    return submeter(run, native, tool, attempt) unless submitted?(run)

    apply(run, native, tool.poll(handle: tool_handle(run), attempt: attempt), attempt)
  rescue MudouDeDono => e
    Rails.logger.warn("[autonomia][tool][async] run=#{run.id} slug=#{run.slug} passada abandonada: #{e.message}")
  rescue StandardError => e
    # NUNCA ecoar e.message: a exceção pode carregar requisição assinada ou texto vindo do
    # portal. Só a classe vai ao log; ao cliente vai a NOSSA frase.
    Rails.logger.warn("[autonomia][tool][async] run=#{run.id} slug=#{run.slug} #{e.class}")
    retry_or_fail(run, native, attempt)
  end

  # A SEGUNDA PORTA DE RECUSA (entrega 6): a conferência do turno passou (ou caiu) e a validação do
  # `start` recusou. A ferramenta devolve handle com `pedido` — o contrato que `poll` já reconhece —
  # e é AQUI, não nela, que se sabe a conversa e o agente. Registrar nunca derruba a execução: a
  # entrega do pedido ao cliente vale mais que a nossa linha de log.
  def registrar_recusa(run, handle)
    handle = handle.to_h.deep_stringify_keys if handle.is_a?(Hash)
    return unless handle.is_a?(Hash) && handle['pedido'].present?

    ::Autonomia::Agents::Tools::Recusa.registrar(handle['motivo'], slug: run.slug, conversa: run.conversation_id,
                                                                   agente: run.agent, faltando: handle['faltando'], onde: 'envio')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] registro de recusa falhou run=#{run.id} #{e.class}")
  end

  # A ORDEM QUE PROTEGE O DINHEIRO (entrega 5; era a janela #337). Entre `tool.start` e o registro do
  # número não há atomicidade: um deploy no meio (o Sidekiq desta instalação re-enfileira o job no
  # hard shutdown, depois dos 25 s de `:timeout`) deixava a cotação feita no portal e não registrada,
  # e a passada seguinte cotava de novo — até 60 vezes, sem ninguém saber.
  #
  # Agora: anota a INTENÇÃO com contador, submete, anota o NÚMERO. Quem volta e encontra intenção sem
  # número sabe que PODE ter enviado — e tenta no máximo mais UMA vez, marcando a execução como
  # possivelmente duplicada (`ToolRun.possivelmente_duplicadas` lista). Na terceira intenção, para:
  # cotar duas vezes é bagunça no portal do corretor; três seria negligência.
  #
  # O que `start` levanta decide o destino da intenção, e a fronteira é a CHAMADA PAGA
  # (`tentar_start`): falha antes dela, ou com o portal dizendo que recusou, apaga a intenção — o
  # login do portal falha sozinho de vez em quando, e a anotação não pode virar sentença de "já foi"
  # e travar a conversa. Falha DEPOIS de a chamada sair, sem o portal dizer nada (timeout, 502,
  # resposta ilegível), mantém a intenção: o portal pode ter cotado.
  #
  # As duas escritas são compare-and-set sobre a intenção que esta passada leu (`MudouDeDono`).
  MAXIMO_DE_INTENCOES = 2

  def submeter(run, native, tool, attempt)
    intencao = run.intencoes + 1
    return fail_run(run, native, 'envio_incerto') if intencao > MAXIMO_DE_INTENCOES

    anotar_intencao!(run, atual: intencao - 1, para: intencao)
    handle = tentar_start(run, tool, intencao)
    registrar_recusa(run, handle)
    registrar_numero!(run, handle, intencao)
    reschedule(run, attempt)
  end

  # Grava `para` no lugar de `atual` — só se a linha ainda estiver em `atual` e sem número (a posse).
  # Serve para anotar (0→1, 1→2) e para voltar atrás quando o portal disse que não fez (1→0, 2→1).
  # A marca de duplicata é MONOTÔNICA enquanto a execução vive: voltar de 2 para 1 a MANTÉM, porque a
  # primeira chamada continua incerta (é por isso que a intenção 1 ficou) — tirá-la apagava a marca
  # que um desfecho concorrente acabava de gravar (Codex, rodada 3). Só a volta a zero a tira: a
  # única chamada feita falhou com certeza.
  def anotar_intencao!(run, atual:, para:)
    gravou = run.merge_handle!(marcas_de_intencao(para), remover: para.zero? ? MARCAS_DE_INTENCAO : [],
                                                         intencao: atual)
    raise MudouDeDono, "intenção #{atual}→#{para} não gravou" unless gravou
    return unless para > 1

    Rails.logger.warn("[autonomia][tool][async] possivelmente duplicada run=#{run.id} slug=#{run.slug} intencao=#{para}")
  end

  def marcas_de_intencao(numero)
    return {} if numero.zero?
    return { ToolRun::INTENCOES => numero } if numero == 1

    { ToolRun::INTENCOES => numero, ToolRun::POSSIVELMENTE_DUPLICADA => true }
  end

  # O que `start` levanta decide o destino da intenção:
  #   - `Native::EnvioIncerto`: a ferramenta chamou o portal e ninguém disse se valeu. A intenção
  #     FICA; a passada seguinte tenta no máximo mais uma vez, marcada.
  #   - qualquer outro `StandardError`: a falha veio ANTES da chamada paga (login, conexão ausente,
  #     validação) ou o portal DISSE que não fez. A intenção volta ao que era.
  #   - `Sidekiq::Shutdown` é `Interrupt`, não `StandardError`: no desligamento nada aqui roda, e é
  #     assim que a intenção sobrevive ao caso para o qual ela existe. Um `rescue Exception` a
  #     apagaria exatamente ali; `intencao_de_envio_spec` reprova.
  # Nos dois primeiros casos a exceção segue para `advance`, que decide entre tentar de novo e
  # desistir.
  def tentar_start(run, tool, intencao)
    tool.start
  rescue ::Autonomia::Agents::Tools::Native::EnvioIncerto => e
    Rails.logger.warn("[autonomia][tool][async] envio incerto run=#{run.id} slug=#{run.slug} intencao=#{intencao} motivo=#{e.motivo}")
    raise
  rescue StandardError
    anotar_intencao!(run, atual: intencao, para: intencao - 1)
    raise
  end

  # O NÚMERO, guardado pela mesma intenção. Se não grava, outro processo passou na frente ou a
  # execução morreu: a cotação que este `start` abriu fica sem registro nosso — e é por isso que a
  # marca de duplicata é gravada por quem anota a SEGUNDA intenção, não por quem chega por último.
  def registrar_numero!(run, handle, intencao)
    return if run.record_attempt!(handle: submitted_handle(handle), intencao: intencao)

    raise MudouDeDono, "número da intenção #{intencao} não gravou"
  end

  def apply(run, native, progress, attempt)
    Array(progress&.deliveries).each { |entrega| deliver(run, entrega) }
    run.record_attempt!(handle: merged_handle(progress&.handle))

    if progress.nil? || progress.failed?
      fail_run(run, native, progress&.failure_code)
    elsif progress.done?
      finish_done(run, native)
    else
      reschedule(run, attempt)
    end
  end

  # Entrega da FERRAMENTA (não o aviso, não a frase de falha). Conta como entregue tanto a publicada
  # quanto a ADIADA — a adiada sai sozinha pelo `AsyncPublishJob`, e tratá-la como "nada entregue"
  # faria o desfecho publicar "não consegui concluir" ao lado da cotação que estava a caminho.
  # `entrega` é texto ou a forma serializada de uma entrega de arquivo (o comparativo, entrega 11).
  #
  # DUAS ANOTAÇÕES, A MESMA PERGUNTA (entrega 8a): o contador diz QUANTAS entregas o publicador
  # aceitou, e o registro do aceite (`Tools::EntregaAceita`) diz QUAIS. O contador não basta para o
  # fecho — ele soma qualquer item aceito, inclusive a pergunta pelo dado que falta —, e as duas
  # anotações acontecem no ACEITE, não na emissão: o handle da ferramenta só vai ao banco no
  # `record_attempt!` seguinte.
  def deliver(run, entrega)
    result = ::Autonomia::Agents::Tools::EntregaAceita.registrar(run, entrega, publish(run, entrega))
    run.record_delivery! if result.aceita?
    result
  end

  # Terminou sem NADA entregue (todas as seguradoras mudas, por exemplo): o cliente precisa saber.
  # Terminar em silêncio é o pior desfecho para quem está esperando — e dizer "não consegui" ao lado
  # de uma cotação entregue é o segundo pior.
  def finish_done(run, native)
    publish(run, native.failure_message) if run.delivered_count.zero?
    run.finish!('done')
  end

  # ACABAR SEM FECHAR TAMBÉM É UM DESFECHO, E QUEM DECIDE O QUE AINDA VALE É A FERRAMENTA. Em
  # 08/09/2026 uma cotação entregou cinco preços, estourou o prazo, e a conversa simplesmente parou,
  # sem comparativo e sem uma palavra. A correção de então condicionou o encerramento a
  # `delivered_count` positivo, e sobrou o defeito simétrico (Codex, entrega 8, P2): com o prazo
  # vencendo ANTES da primeira entrega, um arquivo já gerado morre no handle e o cliente lê "não
  # consegui" ao lado de um PDF que existia.
  #
  # Agora o encerramento é SEMPRE oferecido à ferramenta, e o filtro mora nela, que é quem sabe o que
  # tem em mãos. PARA A COTAÇÃO NADA MUDA no que sai: `comparison_pdf` devolve nil sem `entregues` no
  # handle (`InsuranceQuote::Comparativo`), então a execução que morre sem preço nenhum continua
  # fechando com a frase de falha e sem pedir nada ao portal — travado por exemplo pelo caminho real
  # em `async_run_job_encerramento_parcial_spec`.
  #
  # Quem acaba com intenção anotada e sem número (entrega 5) fica marcado para a lista do corretor,
  # seja qual for o código do desfecho: prazo esgotado ou terceira intenção, a cotação pode existir.
  # Quem marca é o `finish!`, no mesmo comando que encerra — uma intenção anotada por outro processo
  # no meio não escapa. Aqui só se RECARREGA: a frase ao cliente sai do estado do banco, não de uma
  # leitura velha (um objeto que ainda diz "intenção sem número" quando outro processo já registrou).
  def fail_run(run, native, code)
    run.reload
    encerrar(run, native) if native.present?
    run.finish!('failed', failure_code: code.presence || 'tool_failed')
  end

  # O ENCERRAMENTO É UM SÓ, e mora em `Tools::Encerramento` (entrega 8): a mesma sequência — adquirir
  # a marca, oferecer as entregas à ferramenta, publicar o fecho — vale para o VARREDOR, que fecha a
  # linha quando ESTA corrente de jobs se rompe. Ele ficava com metade dela, e o cliente lia "não
  # consegui" com o arquivo pronto parado no handle.
  #
  # Aqui a publicação ESPERA a cadeia de entrega humanizada do turno e re-agenda a adiada — é o que
  # `publish` faz, e é por isso que quem publica é quem chama.
  def encerrar(run, native)
    ::Autonomia::Agents::Tools::Encerramento
      .new(run: run, native: native) { |entrega| publish(run, entrega) }
      .encerrar
  end

  # A ferramenta montada para trabalhar FORA do turno: com a LINHA (é pelo `delivery_token` dela que
  # se monta a identidade de cada entrega) e SEM `delivery`, de propósito: a presença do `delivery`
  # é o que diz "dentro do turno" para quem escolhe a sessão por ela.
  #
  # QUEM LÊ A LINHA É O FECHO DA COTAÇÃO (entrega 8a): com ela a ferramenta monta a identidade de
  # cada entrega que emite (`EntregaPublicada.token_de`) e, no encerramento, pergunta ao registro do
  # ACEITE (`EntregaAceita`) o que o publicador assumiu. Nasce com padrão `nil` em `Native::Base`, e
  # quem não a usa não muda de comportamento.
  def ferramenta(run, native)
    native.new(agent: run.agent, params: run.arguments, run: run)
  end

  # Parada por decisão do operador: sem mensagem ao cliente. Publicar aqui seria furar exatamente o
  # gate que mandou parar.
  def block_run(run)
    run.finish!('blocked', failure_code: 'nao_autorizado')
  end

  def retry_or_fail(run, native, attempt)
    run.record_attempt!
    return fail_run(run, native, 'tool_failed') if run.expired? || attempt + 1 >= AsyncConfig::MAX_ATTEMPTS

    reschedule(run, attempt)
  end

  def reschedule(run, attempt)
    self.class.set(wait: AsyncConfig.interval_for(run.agent, attempt))
        .perform_later(run.id, attempt + 1)
  end

  # A publicação é ADIADA enquanto a entrega humanizada do turno ainda está em curso —
  # publicar no meio dela entregaria a cotação antes da frase que a promete. A entrega de arquivo
  # viaja para o job adiado na forma serializada (Hash de texto), que é o que o Sidekiq carrega.
  def publish(run, entrega)
    result = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(entrega)
    if result.deferred?
      ::Autonomia::Agents::Tools::AsyncPublishJob
        .set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
        .perform_later(run.id, entrega, 1)
    end
    result
  end

  # "Já submeti?" é a NOSSA marca, não o conteúdo do handle. Sem ela, uma ferramenta que devolvesse
  # nil ou {} no `start` faria a passada seguinte submeter de novo — até 60 vezes, cada uma uma
  # cotação real no portal, que é exatamente o custo que este job existe para evitar.
  def submitted?(run)
    run.handle.is_a?(Hash) && run.handle[SUBMITTED_KEY].present?
  end

  # As marcas NOSSAS no handle: submetido, intenções, possivelmente duplicada, encerrado, e a lista
  # do aceite. A ferramenta não as vê (`tool_handle`) e não as escreve (`parte_da_ferramenta`); elas
  # só mudam por escritas mescladas no banco (`ToolRun#merge_handle!`, `#record_attempt!`,
  # `#registrar_entrega_aceita!`), nunca por cópia da memória.
  #
  # A LISTA DO ACEITE PRECISA ESTAR AQUI, e não é detalhe: ela é escrita NO MEIO da passada, e o
  # handle que a ferramenta devolve foi lido ANTES. Se ela viajasse no handle da ferramenta, o
  # `record_attempt!` do fim da passada a regravaria com a cópia velha — o token recém-aceito
  # sumiria. A ferramenta a lê pela LINHA (`Tools::EntregaAceita.aceita?`), nunca pelo handle.
  # É EXATAMENTE O QUE ACONTECE com a lista de identidades da ferramenta, que não é marca e por
  # isso É regravada (medido na rodada 6; issue R19 (#418)).
  #
  # A LISTA TAMBÉM É A FRONTEIRA DO QUE A FERRAMENTA PODE ESCREVER: `ToolRun` recusa
  # `registrar_identidade_emitida!` em qualquer chave desta lista, para que a ferramenta não
  # invente um aceite nem cale o encerramento gravando `autonomia_closed`.
  MARCAS = [SUBMITTED_KEY, CLOSED_KEY, ToolRun::INTENCOES, ToolRun::POSSIVELMENTE_DUPLICADA, ToolRun::PEDIDO,
            ToolRun::ENCERRADA_EM, ToolRun::ENTREGAS_ACEITAS].freeze
  MARCAS_DE_INTENCAO = [ToolRun::INTENCOES, ToolRun::POSSIVELMENTE_DUPLICADA].freeze

  # O handle da FERRAMENTA, sem as nossas marcas: ela não precisa conhecer o nosso controle — nem
  # na consulta, nem no fechamento.
  def tool_handle(run)
    run.handle.to_h.except(*MARCAS)
  end

  # O que vai ao banco depois do `start`: a parte da ferramenta mais "submetido", MESCLADA por cima
  # do que está lá. As marcas da linha ficam onde estão; uma marca que a ferramenta tenha inventado
  # não entra.
  def submitted_handle(handle)
    parte_da_ferramenta(handle).merge(SUBMITTED_KEY => true)
  end

  # A consulta só atualiza o handle quando a ferramenta devolve um novo.
  def merged_handle(handle)
    return nil unless handle.is_a?(Hash) && handle.present?

    submitted_handle(handle)
  end

  def parte_da_ferramenta(handle)
    (handle.is_a?(Hash) ? handle : {}).except(*MARCAS)
  end
end
