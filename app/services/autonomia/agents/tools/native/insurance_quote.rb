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
  # QUANTAS SEGURADORAS ESTA COTAÇÃO ACIONOU (entrega 7). Os códigos de TODAS as que o portal pôs na
  # cotação — cotou, recusou o risco ou recusou a nossa credencial —, que é a unidade que a corretora
  # paga. `DELIVERED_KEY` não serve para isso: ele guarda quem COTOU, que é o que já foi para o
  # cliente; na renovação real de 11/09/2026 eram onze de dezessete, e as outras seis não deixavam
  # rastro nenhum. Sem esta chave, medir para cobrar seria contar execuções e chamá-las de consultas.
  ACIONADAS_KEY = 'seguradoras_acionadas'.freeze
  # A PROPOSTA INDIVIDUAL, quando ela existir (entrega 8): os códigos das seguradoras cuja proposta
  # saiu nesta cotação. A ferramenta de proposta por seguradora ainda não existe — `quote/proposal`
  # com `insurer_code` é o caminho, e `comparison_pdf` já usa o mesmo endpoint SEM código para o
  # comparativo. O ponto de registro é este handle, na passada que gerar a proposta; a medida da
  # entrega 7 já conta a lista (`Insurance::Medida`), e hoje conta zero porque ninguém a escreve.
  PROPOSTAS_KEY = 'propostas'.freeze
  # O PDF já foi EMITIDO? O comparativo sai UMA vez, no fim — não a cada entrega parcial. A
  # sentinela é gravada quando a ENTREGA sai da ferramenta, seja qual for a forma em que o
  # publicador a faça chegar (arquivo, ou o link de reserva quando o download falha).
  #
  # EMITIDO NÃO É ENTREGUE, e esta chave nunca soube a diferença: ela é gravada quando a entrega sai
  # daqui, antes de o publicador dizer se a mensagem entrou. Quem precisa saber se o cliente TEM o
  # comparativo pergunta pelo `COMPARATIVO_KEY`, que é a identidade da mensagem, à conversa.
  PDF_SENT_KEY = 'comparativo_enviado'.freeze
  # O QUE ESTA EXECUÇÃO EMITIU, PELA IDENTIDADE QUE CADA ENTREGA TEM COMO MENSAGEM (entrega 8a).
  # O handle é a INTENÇÃO de quem publicou; a mensagem é o FATO, e os dois divergem sempre que a
  # publicação volta `blocked` depois de o handle já ter avançado — `deliver` roda ANTES de
  # `record_attempt!`, então uma entrega bloqueada (conversa encerrada, agente desligado no meio,
  # erro transitório do publicador) avança o handle com os códigos das ofertas mesmo sem mensagem
  # nenhuma. Guardar o TOKEN é o que permite ao fecho fazer a pergunta do fato
  # (`Tools::EntregaPublicada`): o handle diz o que procurar, a conversa diz se chegou.
  PRECOS_KEY = 'entregas_de_preco'.freeze
  COMPARATIVO_KEY = 'entrega_do_comparativo'.freeze
  # O PORTAL FECHOU A COTAÇÃO — `completed` ou `failed` na consulta, que é o que `finished?` lê.
  # É FATO DO PORTAL, gravado por quem o leu, e não se deduz do comparativo: uma cotação que fecha
  # sem URL de comparativo (geração indisponível, portal sem arquivo) não grava `PDF_SENT_KEY`
  # nenhum, e ler a ausência como "ainda tem seguradora por responder" é a frase de atraso dita a
  # quem já recebeu tudo o que ia chegar.
  FECHADO_KEY = 'portal_fechado'.freeze
  # Renovação cotada sem a classe de bônus. Viaja no handle porque quem decide isso é o `start`, e
  # quem precisa contar ao cliente é a primeira entrega de preços, minutos depois.
  SEM_BONUS_KEY = 'renovacao_sem_bonus'.freeze
  # O aviso JÁ SAIU. Sentinela própria, no mesmo molde do `PDF_SENT_KEY`, e não inferência a partir
  # de `already.empty?`: `deliver` roda ANTES de `record_attempt!`, então uma entrega bloqueada
  # (conversa encerrada, erro transitório do publisher) avançava o handle com os códigos das ofertas
  # mesmo assim — e o aviso, que vale por sair UMA vez, não sairia nunca mais.
  AVISO_SENT_KEY = 'aviso_sem_bonus_enviado'.freeze
  # Por seguradora, POR QUE o preço saiu sem período (entrega 13, termo 1): o motivo do adapter, que
  # nomeia o campo do portal que faltou ou veio ambíguo. Fica no handle da execução, consultável
  # depois em `autonomia_agent_tool_runs.handle->'preco_sem_periodo'`, sem reabrir a cotação.
  SEM_PERIODO_KEY = 'preco_sem_periodo'.freeze
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
  include Veiculo
  include Comparativo
  include Fecho

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
    return recusa('formulario_indisponivel', FALHOU, faltando: []) if sem_formulario?
    return recusa('sem_veiculo', SEM_VEICULO_CLIENTE, faltando: [PLACA]) if sem_veiculo?

    faltantes = validar
    return recusa('faltam_dados', pedido_do_que_falta(faltantes), faltando: campos(faltantes)) if faltantes.any?

    submeter
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :not_implemented

    recusa('ramo_desconhecido', RAMO_DESCONHECIDO, faltando: ['produto'])
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
    return conferencia('formulario_indisponivel', SEM_FORMULARIO, []) if sem_formulario?
    return conferencia('sem_veiculo', SEM_VEICULO, [PLACA]) if sem_veiculo?

    faltantes = validar
    faltantes.any? ? conferencia('faltam_dados', conferencia_para_o_modelo(faltantes), campos(faltantes)) : nil
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
  # velha do nosso lado, e mandar o agente perguntar por causa disso seria atrito sem causa. Os
  # problemas que só o chat2you enxerga (`Veiculo#problemas_locais`) entram na mesma lista, no mesmo
  # formato: o modelo lê `campo — motivo` de um jeito só.
  def validar
    Array(validacao&.dig('problemas')).select { |p| p['severidade'] == 'erro' } + problemas_locais
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
    leitura = ofertas.new(result)
    already = Array(handle[DELIVERED_KEY]).map(&:to_s)
    fresh = leitura.quoted.reject { |offer| already.include?(ofertas.code(offer)) }
    next_handle = handle.merge(DELIVERED_KEY => already + fresh.map { |offer| ofertas.code(offer) },
                               ACIONADAS_KEY => acionadas(leitura, handle))
    deliveries, next_handle = precos(fresh, already, next_handle)

    return progress_class.running(deliveries: deliveries, handle: next_handle) unless finished?(result)

    # O PORTAL FECHOU, e isso se grava por si: é o fato que separa "ainda tem seguradora por
    # responder" de "é isto que havia", e ele não pode depender de o comparativo ter saído.
    fechar(deliveries, next_handle.merge(FECHADO_KEY => true))
  end

  # O comparativo em PDF fecha a conversa, e sai UMA vez. É o que o portal entrega e o que o
  # cliente guarda — a lista de preços no chat serve para decidir, o PDF serve para levar adiante.
  # Desde a entrega 11 ele é uma entrega de ARQUIVO (`Comparativo`), não um texto com link.
  #
  # Duas marcas, e elas dizem coisas diferentes: `PDF_SENT_KEY` é "já emiti este comparativo" (o
  # que impede a segunda emissão) e `COMPARATIVO_KEY` é a IDENTIDADE da mensagem que ele vira — é
  # por ela que o fecho pergunta ao banco se o cliente o recebeu. `compact` porque sem execução não
  # há identidade a gravar.
  def fechar(deliveries, handle)
    pdf = comparison_pdf(handle)
    return progress_class.done(deliveries: deliveries, handle: handle) if pdf.nil?

    progress_class.done(deliveries: deliveries + [pdf],
                        handle: handle.merge(PDF_SENT_KEY => true, COMPARATIVO_KEY => token_da_entrega(pdf)).compact)
  end

  # A UNIÃO DAS CONSULTAS, não a foto da última (entrega 7). O portal responde em pedaços — medido em
  # 04/09/2026: 3 de 6 seguradoras devolveram preço em ~35 s e o negócio só assentou aos 392 s —, e
  # nada garante que uma consulta liste tudo o que a anterior listou. Gravar a foto apagaria
  # seguradoras que a corretora já acionou e pagou. União é idempotente: reconsulta não muda nada.
  def acionadas(leitura, handle)
    (Array(handle[ACIONADAS_KEY]).map(&:to_s) | leitura.acionadas).sort
  end

  # -> [deliveries, handle]. O aviso de renovação sem bônus tem SENTINELA própria, no mesmo molde do
  # PDF, e não é inferido de "esta é a primeira entrega".
  def precos(fresh, already, handle)
    return [[], handle] if fresh.empty?

    avisar = handle[SEM_BONUS_KEY].present? && handle[AVISO_SENT_KEY].blank?
    texto = ::Autonomia::Insurance::QuoteOffers.describe(
      fresh, first: already.empty?, aviso: avisar ? AVISO_SEM_BONUS : nil
    )
    handle = registrar_entrega_de_preco(texto, registrar_sem_periodo(fresh, handle))
    [[texto], avisar ? handle.merge(AVISO_SENT_KEY => true) : handle]
  end

  # A IDENTIDADE DA MENSAGEM QUE ESTE PREÇO VAI VIRAR, guardada na passada que o emite — é a única
  # em que se sabe o TEXTO, e é do texto que o token nasce. Quem lê é o fecho, que pergunta à
  # conversa se a mensagem existe: o contador da execução não serve (conta qualquer item aceito,
  # inclusive a pergunta pelo dado que falta) e a lista de `entregues` também não (ela avança mesmo
  # quando a publicação é recusada). ACUMULA, porque cada lote de preços é uma mensagem.
  # Sem execução não há token, e aí não se grava nada: o fecho cala, que é o lado conservador.
  def registrar_entrega_de_preco(texto, handle)
    token = token_da_entrega(texto)
    return handle if token.blank?

    handle.merge(PRECOS_KEY => (Array(handle[PRECOS_KEY]).map(&:to_s) + [token]).uniq)
  end

  # O token de uma entrega DESTA execução, pela mesma definição que o publicador usa.
  def token_da_entrega(entrega)
    ::Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
  end

  # O registro ACUMULA entre lotes (o lote 2 não pode apagar o motivo do lote 1) e só escreve a
  # chave quando há o que registrar. `fresh` já é a lista de quem cotou.
  def registrar_sem_periodo(fresh, handle)
    motivos = ::Autonomia::Insurance::QuoteOffers.new('offers' => fresh).sem_periodo
    return handle if motivos.empty?

    handle.merge(SEM_PERIODO_KEY => handle[SEM_PERIODO_KEY].to_h.merge(motivos))
  end

  def finished?(result)
    %w[completed failed].include?(result['status'])
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
