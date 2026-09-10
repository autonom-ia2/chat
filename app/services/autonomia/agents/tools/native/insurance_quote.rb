# Cotação de seguro em QUALQUER ramo que a corretora atende (#350).
#
# UMA FERRAMENTA, ONZE RAMOS. Até 08/09/2026 havia uma ferramenta só de auto, com sete parâmetros
# digitados à mão em Ruby, e nenhuma para os outros dez — que cotam com preço no adapter desde
# 07/09. Um ramo novo era outro arquivo, com os campos daquele ramo digitados de novo, e cada lista
# envelhecendo sozinha.
#
# AUTO NÃO É UM CASO ESPECIAL: é um ramo com UM comportamento extra, o bônus de renovação. Manter
# um arquivo paralelo para ele significava um `if produto == 'auto'` no meio do caminho — e, pior,
# duas conquistas que NÃO são de auto ficavam fora dos outros dez: o comparativo em PDF e o registro
# da seguradora que recusou a credencial da corretora (critério 4.5). Uma seguradora que recusa o
# login numa cotação de bike sumia da lista, e a corretora seguia achando que ela "não cotou esse
# risco" — quando havia um login para arrumar.
#
# O QUE ELA NÃO SABE, E É O PONTO: nada sobre ramo nenhum. Pergunta ao adapter o que o ramo pede
# (`quote/schema`), confere a entrada antes de cotar (`quote/validate`) e, quando falta algo,
# devolve ao agente A LISTA DO QUE FALTA. Cada cotação no AGGER consome consulta paga; a validação
# não toca no portal.
#
# O QUE VAI PARA O CLIENTE, e o que não vai (decisão do PO):
#   - preço de seguradora que cotou: vai;
#   - seguradora que recusou o risco: NÃO vai por iniciativa nossa. O cliente pediu preço, não
#     auditoria, e a recusa fala do bem e da região dele. Só se ele perguntar — e aí quem responde é
#     a instrução do especialista, não esta ferramenta;
#   - credencial da corretora inválida numa seguradora: NUNCA vai, nem se perguntado. É problema
#     nosso, constrangedor e inútil para quem quer comprar. Vai para a tela de Conexões.
class Autonomia::Agents::Tools::Native::InsuranceQuote < Autonomia::Agents::Tools::Native::Base
  # O ramo do automóvel. O único com montagem de entrada própria — ele tem veículo, e o adapter
  # resolve placa e FIPE antes de cotar.
  AUTO = 'auto'.freeze
  # Teto do JSON que o modelo escreve. O ramo que mais pede é a bike, com dezessete campos — alguns
  # milhares de caracteres com folga. Parsear antes de olhar o tamanho é trabalho que ninguém pediu.
  MAX_DADOS_BYTES = 20_000
  DEFAULT_COMMISSION = 10.0
  # Chave nossa dentro do handle: quem já foi entregue. É o que faz a segunda mensagem ser
  # "chegaram mais opções" em vez de repetir as que o cliente já leu.
  DELIVERED_KEY = 'entregues'.freeze
  # O PDF já foi entregue? O comparativo sai UMA vez, no fim — não a cada entrega parcial.
  PDF_SENT_KEY = 'comparativo_enviado'.freeze
  # Renovação cotada sem a classe de bônus. Viaja no handle porque quem decide isso é o `start`, e
  # quem precisa contar ao cliente é a primeira entrega de preços, minutos depois.
  SEM_BONUS_KEY = 'renovacao_sem_bonus'.freeze
  # O aviso JÁ SAIU. Sentinela própria, no mesmo molde do `PDF_SENT_KEY`, e não inferência a partir
  # de `already.empty?`: `deliver` roda ANTES de `record_attempt!`, então uma entrega bloqueada
  # (conversa encerrada, erro transitório do publisher) avançava o handle com os códigos das ofertas
  # mesmo assim — e o aviso, que vale por sair UMA vez, não sairia nunca mais.
  AVISO_SENT_KEY = 'aviso_sem_bonus_enviado'.freeze
  # Sai UMA vez, junto do primeiro preço, e só em renovação de auto sem classe de bônus. Não promete
  # desconto nem percentual: o quanto o bônus abate é decisão de cada seguradora, e prometer número
  # aqui vira preço que a emissão desmente. Diz o que é verdade — existe preço melhor, e ele depende
  # de um dado que está na apólice do cliente.
  AVISO_SEM_BONUS = 'Importante: cotei sem a classe de bônus da sua apólice atual, então estes ' \
                    'preços são os de quem está fazendo o primeiro seguro. Se você conferir a ' \
                    'classe de bônus na apólice (é um número de 0 a 10) e me disser, eu refaço a ' \
                    'cotação — com bônus costuma sair melhor.'.freeze

  include Declaracao
  include Recusas
  include Envio

  # -> Hash serializável guardado na execução. Volta rápido: quem espera é o job.
  #
  # NÃO COTA ANTES DE VALIDAR. Cada cotação no AGGER consome consulta paga, e conferir a entrada
  # custa uma chamada que não toca no portal.
  #
  # RAMO QUE O ADAPTER NÃO TEM É RECUSA, NÃO FALHA. `produto` é escrito pelo modelo; antes, um ramo
  # desconhecido levantava aqui a cada passada, o job tentava 60 vezes por 7 minutos e fechava em
  # `tool_failed` — o cliente esperava tudo isso por "não consegui", e nada dizia o motivo.
  def start
    return recusa('json_invalido', FALTA_ALGO, faltando: ['dados']) if dados.nil?

    faltantes = validar
    return recusa('faltam_dados', pedido_do_que_falta(faltantes), faltando: campos(faltantes)) if faltantes.any?

    submeter
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :not_implemented

    recusa('ramo_desconhecido', RAMO_DESCONHECIDO, faltando: ['produto'])
  end

  # O COMPARATIVO NÃO PODE SER REFÉM DA SEGURADORA MAIS LENTA. Ele era gerado só no ramo `done`,
  # quando o portal marcava a cotação como `completed` — e em 08/09/2026 a execução entregou cinco
  # preços e estourou o prazo na 22ª consulta, então o PDF nunca saiu. O comparativo é o que o
  # cliente leva para decidir; os preços soltos no chat são o resumo dele.
  def closing_deliveries(handle)
    [comparison_pdf(handle.to_h)].compact
  end

  # A IDENTIDADE DO PEDIDO (entrega 10): digest da entrada como o ADAPTER a entende — transformações
  # e padrões dele, devolvidos pelo `quote/validate` — mais o produto. É com isto que o `Bound` sabe
  # que "e aí, saiu?" é o mesmo pedido. nil quando a conferência caiu, ou quando o adapter ainda
  # não devolve a entrada: nil nunca barra, e o custo é a duplicata que já existia.
  def pedido
    ::Autonomia::Insurance::Pedido.digest(produto, validacao&.dig('entrada'))
  rescue ::Autonomia::Insurance::Connector::Error
    nil
  end

  # A MESMA CONFERÊNCIA DO `start`, só que a tempo de servir para alguma coisa. Roda dentro do turno
  # e devolve texto ao modelo, que pede o dado que falta em vez de anunciar uma cotação que a
  # validação vai recusar cinco segundos depois — foi o que aconteceu em 08/09/2026.
  #
  # Não toca no portal e tem teto próprio de 10 s (`Connector::Http::CONFERENCIA_TIMEOUT`), então
  # não segura o turno. Qualquer falha aqui devolve nil — menos ramo desconhecido, que é recusa
  # nomeada —: conferência é conferência, não portão, e a regra de `validar` continua sendo "não
  # deixar de cotar por causa do conferente".
  #
  # Devolve a `Conferencia` inteira, não só a frase: o registro de recusa (entrega 6) precisa saber
  # QUAIS campos faltaram, e a frase em português já traduziu os nomes.
  def precheck
    return conferencia('json_invalido', PEDIDO_DE_JSON, ['dados']) if dados.nil?

    faltantes = validar
    faltantes.any? ? conferencia('faltam_dados', pedido_do_que_falta(faltantes), campos(faltantes)) : nil
  rescue ::Autonomia::Insurance::Connector::Error => e
    # Ramo desconhecido é a única falha de validação que a conferência NÃO deixa passar: aceitar
    # abriria uma execução que o `start` recusaria de qualquer jeito, minutos depois.
    return conferencia('ramo_desconhecido', RAMO_DESCONHECIDO, ['produto']) if e.kind == :not_implemented

    Rails.logger.warn("[autonomia][insurance] conferencia indisponivel account=#{account.id} #{e.kind}")
    nil
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] conferencia indisponivel account=#{account.id} #{e.class}")
    nil
  end

  # -> Tools::Progress. Uma consulta. Só entrega quem AINDA NÃO foi entregue.
  def poll(handle:, attempt:)
    return progress_class.done(deliveries: [handle['pedido']], handle: handle) if handle['pedido']

    quote_id = handle['quote_id']
    return progress_class.failed('sem_id_de_cotacao') if quote_id.blank?

    result = sessions.with_fresh_session do |open_session|
      connector.quote_result(provider: connection.provider, session: open_session, quote_id: quote_id)
    end
    build_progress(result, handle, attempt)
  end

  private

  # O QUE FALTA, PERGUNTADO DE GRAÇA. Só `erro` vira pedido: `aviso` fala de tabela possivelmente
  # velha do nosso lado, e mandar o agente perguntar por causa disso seria atrito sem causa.
  def validar
    Array(validacao&.dig('problemas')).select { |p| p['severidade'] == 'erro' }
  end

  # A conferência gratuita, UMA vez por instância: `precheck` lê os problemas e `pedido` lê a
  # entrada normalizada do mesmo retorno. nil quando o conferente caiu.
  def validacao
    return @validacao if defined?(@validacao)

    @validacao = connector.quote_validate(provider: connection.provider, product: produto, input: entrada)
  rescue ::Autonomia::Insurance::Connector::Error => e
    # PRODUTO DESCONHECIDO É ERRO DE VERDADE e sobe, para `start` e `precheck` traduzirem em recusa
    # nomeada; qualquer outra falha da validação não pode impedir a cotação, porque ela é uma
    # CONFERÊNCIA e não um portão. Ficar sem cotar por causa do conferente seria trocar um risco de
    # dinheiro por uma certeza de atendimento perdido.
    raise if e.kind == :not_implemented

    Rails.logger.warn("[autonomia][insurance] validacao indisponivel account=#{account.id} #{e.kind}")
    @validacao = nil
  end

  # A entrada é montada ANTES da chamada paga, fora da fronteira de incerteza (`Envio`): um erro
  # aqui é falha comum, não "pode ter cotado". Na prática ela já está pronta — `validar` a usou —,
  # mas a fronteira não pode depender disso.
  def submeter
    pedido = { provider: connection.provider, product: produto, input: entrada }
    quote_id = sessions.with_fresh_session { |open_session| enviar(open_session, pedido) }
    { 'quote_id' => quote_id, DELIVERED_KEY => [], 'produto' => produto,
      SEM_BONUS_KEY => quote_input.auto? && quote_input.renewal.sem_bonus? }
  end

  def build_progress(result, handle, _attempt)
    registrar_credencial_de_seguradora(result)
    ofertas = ::Autonomia::Insurance::QuoteOffers
    already = Array(handle[DELIVERED_KEY]).map(&:to_s)
    fresh = ofertas.new(result).quoted.reject { |offer| already.include?(ofertas.code(offer)) }
    next_handle = handle.merge(DELIVERED_KEY => already + fresh.map { |offer| ofertas.code(offer) })
    deliveries, next_handle = precos(fresh, already, next_handle)

    return progress_class.running(deliveries: deliveries, handle: next_handle) unless finished?(result)

    # O comparativo em PDF fecha a conversa, e sai UMA vez. É o que o portal entrega e o que o
    # cliente guarda — a lista de preços no chat serve para decidir, o PDF serve para levar adiante.
    pdf = comparison_pdf(next_handle)
    if pdf
      deliveries += [pdf]
      next_handle = next_handle.merge(PDF_SENT_KEY => true)
    end
    progress_class.done(deliveries: deliveries, handle: next_handle)
  end

  # -> [deliveries, handle]. O aviso de renovação sem bônus tem SENTINELA própria, no mesmo molde do
  # PDF, e não é inferido de "esta é a primeira entrega".
  def precos(fresh, already, handle)
    return [[], handle] if fresh.empty?

    avisar = handle[SEM_BONUS_KEY].present? && handle[AVISO_SENT_KEY].blank?
    texto = ::Autonomia::Insurance::QuoteOffers.describe(
      fresh, first: already.empty?, aviso: avisar ? AVISO_SEM_BONUS : nil
    )
    [[texto], avisar ? handle.merge(AVISO_SENT_KEY => true) : handle]
  end

  def finished?(result)
    %w[completed failed].include?(result['status'])
  end

  # nil quando não há o que imprimir, quando já foi enviado, ou quando a geração falha. Nunca
  # derruba a cotação: os preços já chegaram, e um PDF que não sai não pode apagá-los.
  def comparison_pdf(handle)
    return if handle[PDF_SENT_KEY]
    return if Array(handle[DELIVERED_KEY]).empty?

    proposal = sessions.with_fresh_session do |open_session|
      connector.quote_proposal(provider: connection.provider, session: open_session,
                               quote_id: handle['quote_id'])
    end
    url = proposal.to_h['url'].presence
    url && "Comparativo com todas as opções:\n#{url}"
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] comparativo falhou account=#{account.id} #{e.class}")
    nil
  end

  # CRITÉRIO 4.5 — problema de credencial de seguradora nunca chega ao cliente final; vai para a
  # tela de Conexões. Vale para os ONZE ramos: uma seguradora que recusa o login da corretora numa
  # cotação de bike sumia da lista, e a corretora seguia achando que ela não cotou aquele risco.
  #
  # `cfg/seguradora/config` não denuncia: ele responde `credenciaisValidas: true` até para
  # seguradora com login inválido. A cotação real é a única testemunha, e é aqui que ela passa.
  def registrar_credencial_de_seguradora(result)
    pendentes = ::Autonomia::Insurance::QuoteOffers.new(result).credencial_pendente
    connection.record_insurers_pending_auth!(
      pendentes.map { |offer| ::Autonomia::Insurance::QuoteOffers.code(offer) },
      nomes: pendentes.filter_map { |offer| offer.dig('insurer', 'name') }.uniq
    )
  rescue StandardError => e
    # Diagnóstico não derruba cotação: os preços do cliente valem mais que o nosso registro.
    Rails.logger.warn("[autonomia][insurance] registro de credencial de seguradora falhou #{e.class}")
  end

  # Auto é o padrão quando ninguém diz o produto: é o ramo mais pedido, e era o único que existia
  # antes desta ferramenta — conta que já usava a de auto continua funcionando sem mudar nada.
  def produto
    @produto ||= params['produto'].to_s.strip.presence || AUTO
  end

  # A montagem da entrada mora em `Insurance::QuoteInput`: traduzir o que o modelo escreveu para o
  # formato do adapter é outro trabalho, e misturá-lo com o que decide o que vai para o cliente faz
  # cada campo novo mexer no arquivo errado.
  def quote_input
    @quote_input ||= ::Autonomia::Insurance::QuoteInput.new(
      produto: produto, params: params, dados: dados, commission_percent: commission_percent
    )
  end

  def entrada
    @entrada ||= quote_input.to_h
  end

  # `nil` quando o JSON não presta — diferente de `{}`, que é "o cliente ainda não disse nada" e é
  # entrada legítima na primeira chamada.
  def dados
    return @dados if defined?(@dados)

    bruto = params['dados'].to_s.strip
    return @dados = nil if bruto.bytesize > MAX_DADOS_BYTES

    @dados = bruto.empty? ? {} : parse_json(bruto)
  end

  def parse_json(bruto)
    valor = JSON.parse(bruto)
    valor.is_a?(Hash) ? valor : nil
  rescue JSON::ParserError
    nil
  end

  # Comissão da conexão; sem valor definido, o padrão combinado com o PO. Nunca vem do modelo: um
  # agente que a informasse mudaria o que a corretora ganha por cotação.
  def commission_percent
    value = connection.metadata.to_h['commission_percent']
    value.present? ? value.to_f : DEFAULT_COMMISSION
  end

  # A sessão é ÚNICA por conexão (#330): reusada, nunca aberta por chamada. É o que permite duas
  # cotações simultâneas da mesma corretora sem uma atrapalhar a outra.
  def sessions
    @sessions ||= ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(account).find(&:ready?) ||
                    raise(::Autonomia::Insurance::Connector::Error.new(:config, 'sem conexão pronta'))
  end

  def connector
    @connector ||= ::Autonomia::Insurance::Connector.client
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
