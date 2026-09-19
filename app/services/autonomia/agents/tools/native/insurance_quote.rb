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
#   - preço de seguradora que cotou: vai no comparativo em PDF e, quando o cliente pergunta, na fala da
#     Lia (`ver_resultado_da_cotacao`). Esta ferramenta não publica lista de preço (fatia 3 do #420);
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
  # OS CÓDIGOS DE QUEM COTOU COM PREÇO nesta cotação, união das consultas. O nome é do tempo em que cada
  # preço era publicado num lote; desde a fatia 3 do #420 nenhum é, e a chave continua sendo o que a
  # coluna "Com preço" do Super Admin conta (`Insurance::Medida`) e o que decide pedir o comparativo
  # (`Comparativo#comparativo_por_tentar?`).
  DELIVERED_KEY = 'entregues'.freeze
  # QUANTAS SEGURADORAS ESTA COTAÇÃO ACIONOU (entrega 7). Os códigos de TODAS as que o portal pôs na
  # cotação — cotou, recusou o risco ou recusou a nossa credencial —, que é a unidade que a corretora
  # paga. `DELIVERED_KEY` não serve para isso: ele guarda só quem COTOU; na renovação real de 11/09/2026 eram
  # onze de dezessete, e as outras seis não deixavam
  # rastro nenhum. Sem esta chave, medir para cobrar seria contar execuções e chamá-las de consultas.
  ACIONADAS_KEY = 'seguradoras_acionadas'.freeze
  # A PROPOSTA INDIVIDUAL, quando ela existir (entrega 8): os códigos das seguradoras cuja proposta
  # saiu nesta cotação. A ferramenta de proposta por seguradora ainda não existe — `quote/proposal`
  # com `insurer_code` é o caminho, e `gerar_comparativo` já usa o mesmo endpoint SEM código para o
  # comparativo. O ponto de registro é este handle, na passada que gerar a proposta; a medida da
  # entrega 7 já conta a lista (`Insurance::Medida`), e hoje conta zero porque ninguém a escreve.
  PROPOSTAS_KEY = 'propostas'.freeze
  # O COMPARATIVO DESTA EXECUÇÃO FOI ASSUMIDO PELO PUBLICADOR. O comparativo sai UMA vez, no fim — não a
  # cada entrega parcial. Desde a rodada 2 da fatia 1 do PDF rápido (13/09/2026) a sentinela é gravada
  # por `Comparativo#concluir_passada`, na passada que encontra o comparativo assumido (no caminho comum,
  # o comparativo aceito na passada que o emite, a execução encerra ali e ela não chega a ser gravada); até
  # ali ela era gravada quando a entrega saía da ferramenta, antes do download, e a linha gravada pela
  # versão anterior pode tê-la sem o arquivo. Quem decide se pede outro comparativo é
  # `Comparativo#comparativo_por_tentar?`, que cruza o `COMPARATIVO_KEY` (a identidade da entrega) com a
  # lista do ACEITE e com a conversa. A sentinela só vale sozinha sem identidade gravada, e como prova de
  # portal fechado da linha da versão anterior (`Fecho#portal_fechado?`).
  PDF_SENT_KEY = 'comparativo_enviado'.freeze
  # O QUE ESTA EXECUÇÃO EMITIU, PELA IDENTIDADE DE CADA ENTREGA (entrega 8a). É a TABELA DE
  # CONSULTA do fecho, não a prova: emitir não é entregar — `deliver` roda ANTES de
  # `record_attempt!`, então uma entrega recusada (conversa encerrada, agente desligado no meio,
  # erro transitório do publicador) avança o handle com os códigos das ofertas sem que publicação
  # nenhuma tenha sido assumida.
  #
  # A PROVA É O ACEITE, e ela mora na LINHA (`Tools::EntregaAceita`), gravada pelo publicador no
  # momento em que ele assume a entrega. Estas duas chaves dizem por quais identidades perguntar —
  # é o que a ferramenta sabe e o motor não: para ele, um preço e a pergunta pelo dado que falta são
  # "uma entrega".
  #
  # `PRECOS_KEY` NÃO É MAIS ESCRITA (fatia 3 do #420, a cotação não publica lote de preço). Ela só existe
  # nas execuções abertas antes do deploy, e `Fecho#resultado_entregue?` continua a lendo para elas.
  PRECOS_KEY = 'entregas_de_preco'.freeze
  COMPARATIVO_KEY = 'entrega_do_comparativo'.freeze
  # HAVIA PREÇO EMITIDO ANTES DE ESTA VERSÃO REGISTRAR O ACEITE? Gravada uma vez, na primeira
  # consulta desta versão (`Fecho#marcar_preco_legado`). É a COBERTURA da prova legada — ver `Fecho#prova_legada?`.
  PRECO_LEGADO_KEY = 'preco_legado'.freeze
  # A COTAÇÃO FECHOU — `finished?` respondeu verdade na consulta: o portal disse `completed` ou
  # `failed`, ou toda seguradora listada já tinha desfecho (`QuoteOffers#todas_com_desfecho?`). É
  # gravada por quem leu a consulta, e não se deduz do comparativo: uma cotação que fecha sem URL de
  # comparativo (geração indisponível, portal sem arquivo) não grava `PDF_SENT_KEY` nenhum, e ler a
  # ausência como "ainda tem seguradora por responder" é a frase de atraso dita a quem já recebeu
  # tudo o que ia chegar.
  FECHADO_KEY = 'portal_fechado'.freeze
  # OS CÓDIGOS DA ÚLTIMA LEITURA, quando toda seguradora nela tinha desfecho (`QuoteOffers#assentada`);
  # nil quando não. Gravada a cada consulta; `finished?` a compara com a leitura seguinte.
  LEITURA_ASSENTADA_KEY = 'leitura_assentada'.freeze
  # Renovação cotada sem a classe de bônus. Viaja no handle porque quem decide isso é o `start`, e
  # quem conta ao cliente é a legenda do comparativo (`Comparativo#legenda_do_comparativo`), minutos depois.
  SEM_BONUS_KEY = 'renovacao_sem_bonus'.freeze
  # Por seguradora, POR QUE o preço saiu sem período (entrega 13, termo 1): o motivo do adapter, que
  # nomeia o campo do portal que faltou ou veio ambíguo. Fica no handle da execução, consultável
  # depois em `autonomia_agent_tool_runs.handle->'preco_sem_periodo'`, sem reabrir a cotação.
  SEM_PERIODO_KEY = 'preco_sem_periodo'.freeze
  # Sai na legenda do comparativo, e só em renovação de auto sem classe de bônus. Não promete
  # desconto nem percentual: o quanto o bônus abate é decisão de cada seguradora, e prometer número
  # aqui vira preço que a emissão desmente. Diz o que é verdade — existe preço melhor, e ele depende
  # de um dado que está na apólice do cliente.
  #
  # PERDEU O "(É UM NÚMERO DE 0 A 10)" em 12/09/2026, e não por estilo: a decisão do CEO tirou
  # número de toda frase que o cliente lê, e esta é a CONSTANTE DE RECUO do papel `aviso_sem_bonus` —
  # um recuo que publicasse dígito faria a regra valer para o modelo e não para nós. O que se perde
  # é a dica de qual é a cara do dado na apólice; o que se ganha é a regra sem exceção. O travessão
  # também saiu, pelo mesmo motivo.
  AVISO_SEM_BONUS = 'Importante: cotei sem a classe de bônus da sua apólice atual, então estes ' \
                    'preços são os de quem está fazendo o primeiro seguro. Se você conferir a ' \
                    'classe de bônus na apólice e me disser, eu refaço a cotação: com bônus ' \
                    'costuma sair melhor.'.freeze

  include Declaracao
  include Recusas
  include Envio
  include Veiculo
  include Comparativo
  include Fecho
  include Resultado

  # -> Hash serializável guardado na execução. Volta rápido: quem espera é o job.
  #
  # NÃO COTA ANTES DE VALIDAR. Cada cotação no AGGER consome consulta paga, e conferir a entrada
  # custa uma chamada que não toca no portal.
  #
  # RAMO QUE O ADAPTER NÃO TEM É RECUSA, NÃO FALHA. `produto` é escrito pelo modelo; antes, um ramo
  # desconhecido levantava aqui a cada passada, o job tentava 60 vezes por 7 minutos e fechava em
  # `tool_failed` — o cliente esperava tudo isso por "não consegui", e nada dizia o motivo.
  # AS FRASES SÃO DO ESPECIALISTA (12/09/2026). Cada recusa daqui vira uma `delivery`, que vai
  # direto ao cliente: o texto é o do papel correspondente, escrito por ele no pedido, com recuo
  # para a constante quando a frase não passa na peneira.
  def start
    return recusa('json_invalido', frases[:falta_dado], faltando: ['dados']) if dados.nil?
    return recusa('formulario_indisponivel', frases[:falhou], faltando: []) if sem_formulario?
    return recusa('sem_veiculo', frases[:sem_veiculo], faltando: [PLACA]) if sem_veiculo?

    faltantes = validar
    return recusa('faltam_dados', pedido_do_que_falta(faltantes), faltando: campos(faltantes)) if faltantes.any?

    submeter
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :not_implemented

    recusa('ramo_desconhecido', ramo_desconhecido_ao_cliente, faltando: ['produto'])
  rescue Envio::EntradaRecusada => e
    # Falta dado que o cliente tem, e não há o que tentar de novo (#470): recusa, não falha passageira.
    recusa_da_entrada(e)
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

  # A CONSULTA GRAVA, E NÃO PUBLICA (fatia 3 do #420). Até aqui cada leitura publicava, escrito pelo
  # código, o lote de preços que chegou desde a anterior. Agora o cliente recebe o comparativo e o fecho,
  # e os valores quem escreve é a Lia quando ele pergunta (`ver_resultado_da_cotacao`). Cada leitura grava
  # as marcas de `Resultado#marcas_da_leitura`; a que fecha a cotação pede o comparativo
  # (`Comparativo#fechar`).
  #
  # `marcar_preco_legado` antes das marcas: a primeira passada desta versão grava se a versão anterior já
  # tinha publicado preço (`Fecho#prova_legada?`), olhando `entregues` antes de a leitura o atualizar.
  def build_progress(result, handle, _attempt)
    registrar_credencial_de_seguradora(result)
    leitura = ::Autonomia::Insurance::QuoteOffers.new(result)
    handle = marcar_preco_legado(handle, handle[DELIVERED_KEY])
    next_handle = handle.merge(marcas_da_leitura(result, leitura, handle))

    return em_andamento(next_handle, leitura, handle) unless finished?(result, leitura, handle)

    # A COTAÇÃO FECHOU, e isso se grava por si: é o fato que separa "ainda tem seguradora por
    # responder" de "é isto que havia", e ele não pode depender de o comparativo ter saído.
    fechar(next_handle.merge(FECHADO_KEY => true))
  end

  # A UNIÃO DAS CONSULTAS, não a foto da última (entrega 7). O portal responde em pedaços — medido em
  # 04/09/2026: 3 de 6 seguradoras devolveram preço em ~35 s e o negócio só assentou aos 392 s —, e
  # nada garante que uma consulta liste tudo o que a anterior listou. Gravar a foto apagaria
  # seguradoras que a corretora já acionou e pagou. União é idempotente: reconsulta não muda nada.
  def acionadas(leitura, handle)
    (Array(handle[ACIONADAS_KEY]).map(&:to_s) | leitura.acionadas).sort
  end

  # A COTAÇÃO FECHOU NESTA CONSULTA? Verdade quando o portal disse `completed` ou `failed`, ou quando
  # `QuoteOffers#todas_com_desfecho?` responde verdade com o que o handle trouxe das consultas ANTERIORES
  # (`handle` é o que esta passada recebeu): a união das acionadas e a leitura assentada da passada
  # anterior. Com as duas, a cotação só fecha na segunda leitura seguida com o mesmo conjunto e todas com
  # desfecho — um intervalo de consulta a mais depois do último desfecho.
  #
  # A SEGUNDA METADE EXISTE PORQUE O ADAPTER DEVOLVE `partial` PARA DOIS ESTADOS: "ainda chegando
  # preço" e "portal pronto, algumas recusaram" (`quote.ts`, o status geral). Com preço e qualquer
  # recusa o status nunca é `completed`, e essa execução só acabava no prazo.
  def finished?(result, leitura, handle)
    %w[completed failed].include?(result['status']) ||
      leitura.todas_com_desfecho?(handle[ACIONADAS_KEY], handle[LEITURA_ASSENTADA_KEY])
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
