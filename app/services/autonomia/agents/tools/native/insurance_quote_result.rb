# A LIA VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420).
#
# Ferramenta ASSÍNCRONA de exibição, do principal. Lê o que a cotação mais nova da conversa guardou por
# seguradora (`Insurance::ResultadoDaCotacao`) e não chama o portal.
#
#   - Com preço a mostrar: `precheck` devolve nil e a execução é aberta com o que a Lia leu no turno
#     (`handle_de_abertura`: a cotação e os códigos com preço). O modelo recebe `aceite` e fala; a
#     segunda passada do motor publica os itens desses códigos (`poll`), escritos por `QuoteOffers.item`,
#     e o publicador os adia enquanto a entrega da fala do turno está em curso.
#   - Sem preço a mostrar: `precheck` devolve o texto ao modelo e nenhuma execução é aberta.
#
# A LISTA SAI ATÉ SER ACEITA (decisão do CEO, sétima rodada). A passada que a publica devolve `running`; a seguinte
# confere o aceite e só então encerra, e a lista não aceita sai de novo, pelas tentativas e pelo prazo do motor. O
# encerramento (`closing_deliveries`) é a última tentativa. A cotação lida deixar de ser a mais nova encerra em
# silêncio, e é o certo: o turno que abriu a cotação nova fala.
#
# UMA LISTA POR PEDIDO, E NUNCA A MESMA DUAS VEZES (terceira a sétima rodadas de revisão): as listas de execuções
# anteriores (`InsuranceQuoteResult::Listas`), e o preço cujo lote a própria cotação ainda está enviando, que não
# entra na lista (`ResultadoDaCotacao#a_caminho`).
#
# Os textos desta classe ao modelo não trazem o valor do prêmio nem texto do portal. Trazem o nome da seguradora
# perguntada, o desfecho dela e, quando `Insurance::MotivoDaRecusa` classifica o motivo, a categoria dele (`MOTIVOS`).
#
# Os cinco textos de classe que o motor e o encerramento pedem sem instância são vazios: o publicador
# devolve `skipped` para texto vazio, sem criar mensagem (`AsyncPublisher#texto_de`).
class Autonomia::Agents::Tools::Native::InsuranceQuoteResult < Autonomia::Agents::Tools::Native::Base
  include Listas

  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora

  # O motivo com que `Bound#recusar_pela_conferencia` registra a resposta dada no turno.
  RESPONDIDO_NO_TURNO = 'resultado_respondido_no_turno'.freeze
  # No handle desta execução, gravados na abertura: o id da execução de `cotar_seguro` que a Lia leu, e os
  # códigos a publicar.
  EXECUCAO_KEY = 'execucao_da_cotacao'.freeze
  CODIGOS_KEY = 'seguradoras'.freeze

  # Os textos ao modelo.
  SEM_COTACAO = 'Não há cotação nesta conversa para mostrar. Não invente preço nem seguradora.'.freeze
  NAO_CHEGOU = 'A última cotação desta conversa não chegou às seguradoras, e não há preço dela para mostrar. ' \
               'Não invente preço nem seguradora.'.freeze
  ENVIO_INCERTO = 'Não se confirmou se a última cotação desta conversa chegou às seguradoras, e não há preço dela ' \
                  'para mostrar; um atendente vai conferir. Não invente preço nem seguradora.'.freeze
  SEM_RESULTADO = 'O resultado da cotação desta conversa não ficou guardado para consulta. Não invente preço ' \
                  'nem seguradora; se o cliente quiser ver os preços de novo, ofereça chamar um atendente.'.freeze
  SEM_PRECO_AINDA = 'A cotação ainda está correndo e nenhum preço chegou até agora. Não invente preço nem ' \
                    'seguradora.'.freeze
  PRECOS_A_CAMINHO = 'Os preços desta cotação estão na fila de envio e chegam numa mensagem do sistema. Não escreva ' \
                     'valor e não diga que vai mandar outra lista.'.freeze
  PARTE_A_CAMINHO = 'Parte dos preços está na fila de envio, numa mensagem do sistema, e não entra na lista.'.freeze
  SEM_PRECO = 'Nenhuma seguradora fez proposta nesta cotação. Não invente preço nem seguradora.'.freeze
  NAO_ENCONTRADA = 'Nenhuma seguradora com esse nome está nesta cotação. Não liste as seguradoras: pergunte ao ' \
                   'cliente de qual ele fala.'.freeze
  NAO_ENCONTRADA_AINDA = 'Nenhuma seguradora com esse nome apareceu nesta cotação até agora, e ela ainda está ' \
                         'correndo. Não liste as seguradoras.'.freeze
  LISTA_DEPOIS = 'Os preços saem numa lista logo depois da sua mensagem, escrita pelo sistema. Na sua mensagem, ' \
                 'apresente a lista com as suas palavras, sem escrever valor, sem listar seguradoras e sem ' \
                 'travessão.'.freeze
  AINDA_CORRENDO = 'A cotação ainda está correndo: podem chegar mais preços.'.freeze
  HA_SEM_PROPOSTA = 'Algumas seguradoras não fizeram proposta: só fale delas se o cliente perguntar.'.freeze
  SEM_BONUS = 'Esta cotação foi feita sem a classe de bônus da apólice atual.'.freeze
  SEM_MOTIVO = 'Não há motivo que você possa contar: diga só que ela não fez proposta.'.freeze
  # O que o modelo lê sobre o motivo, por categoria (`Insurance::MotivoDaRecusa::CATEGORIAS`). Nunca o texto do portal.
  MOTIVOS = {
    ::Autonomia::Insurance::MotivoDaRecusa::VEICULO =>
      'O motivo que ela deu é do veículo cotado, e não se sabe qual característica: conte com as suas palavras que ' \
      'ela não aceitou o veículo, sem acrescentar detalhe.',
    ::Autonomia::Insurance::MotivoDaRecusa::REGIAO =>
      'O motivo que ela deu é da região (CEP, circulação ou pernoite), e não se sabe mais que isso: conte com as suas ' \
      'palavras que ela não atende a região, sem acrescentar detalhe.'
  }.freeze
  VAZIO = ''.freeze

  class << self
    def slug
      'ver_resultado_da_cotacao'
    end

    def tool_name
      'Ver resultado da cotação'
    end

    def description
      'Mostra o resultado da cotação desta conversa, com o que as seguradoras já responderam, sem cotar de ' \
        'novo. Use quando o cliente pedir para ver os preços outra vez, perguntar quanto deu uma seguradora ' \
        'ou perguntar se uma seguradora fez proposta. Os preços são publicados pelo sistema depois da sua mensagem.'
    end

    def params
      [{ 'name' => 'seguradora', 'type' => 'string', 'required' => false,
         'description' => 'Nome da seguradora que o cliente perguntou, como ele escreveu. Mais de uma: todos ' \
                          'os nomes neste mesmo campo. null para o resultado inteiro.' }]
    end

    def async?
      true
    end

    # Sem o módulo de seguros ligado não há cotação a consultar. Não exige conexão pronta: lê o banco.
    def available_for?(agent)
      ::Autonomia::Insurance::Config.enabled?(agent.account)
    rescue StandardError
      false
    end

    def accepted_message
      LISTA_DEPOIS
    end

    def waiting_message(_arguments = nil) = VAZIO
    def failure_message(_arguments = nil) = VAZIO
    def uncertain_message(_arguments = nil) = VAZIO
    def partial_message(_arguments = nil) = VAZIO
    def closing_message(_arguments = nil) = VAZIO

    # A lista só vira mensagem enquanto a cotação que a Lia leu no turno for a mais nova da conversa, e enquanto nenhuma
    # lista mais nova já aceita a levou (`lista_levada?`).
    def publicacao_vale?(run)
      execucao = run.handle.to_h[EXECUCAO_KEY]
      return false unless execucao.present? && Resultado.execucao_mais_nova(run.conversation_id)&.id == execucao.to_i

      !lista_levada?(run)
    end
  end

  # -> `Native::Conferencia` com o texto ao modelo quando não há preço a publicar; nil quando há.
  def precheck
    texto, codigos = resposta
    codigos.empty? ? conferencia(RESPONDIDO_NO_TURNO, texto) : nil
  end

  # -> o texto ao modelo quando a execução foi aberta.
  def aceite
    resposta.first
  end

  # -> a cotação lida no turno e os códigos com preço deste pedido. Vazio quando não há preço a publicar.
  def handle_de_abertura
    codigos = resposta.last
    return {} if codigos.empty?

    { EXECUCAO_KEY => resultado.run.id, CODIGOS_KEY => codigos }
  end

  # -> o que a abertura gravou na linha. Sem abertura gravada (o `Bound` não a obteve), a cotação e os
  # códigos lidos agora.
  def start
    abertura = run ? run.handle.to_h.slice(EXECUCAO_KEY, CODIGOS_KEY) : {}
    return abertura if abertura[EXECUCAO_KEY].present?

    { EXECUCAO_KEY => resultado&.run&.id, CODIGOS_KEY => resposta.last }
  end

  # -> `running` com a lista enquanto ela não foi aceita; `done` quando ela foi aceita, quando outra mais nova a levou,
  # quando não sobrou código, ou quando a cotação lida deixou de ser a mais nova. A primeira emissão pede a consulta
  # seguinte logo, para conferir o aceite; a que sai de novo (a anterior não foi aceita) segue a progressão das
  # tentativas, como qualquer passada do motor.
  def poll(handle:, **)
    execucao = handle.to_h[EXECUCAO_KEY].to_i
    texto = lista_vale?(execucao) ? emitir_lista(handle.to_h, execucao) : nil
    return progress_class.done unless texto

    progress_class.running(deliveries: [texto], confirmar_logo: handle.to_h.dig(LISTA_KEY, 'token').blank?)
  end

  # A ÚLTIMA TENTATIVA, no encerramento por prazo, por tentativas ou pelo varredor: a lista que ainda vale e não foi
  # aceita. Não chama o portal, então sai também sem `trabalho_novo`.
  def closing_deliveries(handle, trabalho_novo: true) # rubocop:disable Lint/UnusedMethodArgument
    execucao = handle.to_h[EXECUCAO_KEY].to_i
    lista_vale?(execucao) ? [emitir_lista(handle.to_h, execucao)].compact : []
  end

  private

  def resultado
    return @resultado if defined?(@resultado)

    @resultado = Resultado.da_conversa(conversa_id)
  end

  def conversa_id
    run&.conversation_id || delivery&.conversation&.id
  end

  def seguradora
    params['seguradora'].to_s.strip.presence
  end

  # -> [texto ao modelo, códigos com preço a publicar], calculado uma vez por instância.
  def resposta
    @resposta ||= montar_resposta
  end

  def montar_resposta
    return [SEM_COTACAO, []] if resultado.nil?

    sem_leitura = texto_sem_leitura
    return [sem_leitura, []] if sem_leitura

    seguradora ? por_seguradora : geral
  end

  # -> o texto de quando a cotação encerrada não tem resultado a ler, ou nil. A que ainda corre sem ter gravado
  # resultado (a linha em voo no deploy, ou a que nem consultou o portal) tem: "ainda sem preço". A encerrada
  # com envio incerto pode existir no portal; a encerrada sem número do portal não chegou às seguradoras; a
  # encerrada antes desta versão não guardou o resultado.
  def texto_sem_leitura
    return nil if resultado.correndo?
    return ENVIO_INCERTO if resultado.envio_incerto?
    return NAO_CHEGOU unless resultado.cotou?

    SEM_RESULTADO unless resultado.guardado?
  end

  def geral
    todos = resultado.com_preco
    return [resultado.correndo? ? SEM_PRECO_AINDA : SEM_PRECO, []] if todos.empty?

    codigos = todos - resultado.a_caminho
    return [PRECOS_A_CAMINHO, []] if codigos.empty?

    [avisos_do_geral(parte_a_caminho: codigos.size < todos.size).join("\n"), codigos]
  end

  def avisos_do_geral(parte_a_caminho:)
    [LISTA_DEPOIS, (PARTE_A_CAMINHO if parte_a_caminho), (AINDA_CORRENDO if resultado.correndo?),
     (HA_SEM_PROPOSTA if resultado.sem_proposta?), (SEM_BONUS if resultado.sem_bonus?)].compact
  end

  def por_seguradora
    codigos = resultado.procurar(seguradora)
    return [resultado.correndo? ? NAO_ENCONTRADA_AINDA : NAO_ENCONTRADA, []] if codigos.empty?

    com_preco = resultado.com_preco(codigos) - resultado.a_caminho
    partes = codigos.map { |codigo| fala(codigo) }
    partes = [LISTA_DEPOIS, *partes, (SEM_BONUS if resultado.sem_bonus?)] if com_preco.any?
    [partes.compact.join("\n"), com_preco]
  end

  # O que o modelo lê sobre UMA seguradora.
  def fala(codigo)
    nome = resultado.nome(codigo)
    case resultado.desfecho(codigo)
    when Guardado::COM_PRECO then fez_proposta(nome, codigo)
    when Guardado::AGUARDANDO then "#{nome} ainda não respondeu, e a cotação continua correndo."
    else sem_proposta(nome, resultado.motivo(codigo))
    end
  end

  # O preço que a cotação ainda está enviando não entra na lista (`ResultadoDaCotacao#a_caminho`).
  def fez_proposta(nome, codigo)
    onde = resultado.a_caminho.include?(codigo) ? 'está na fila de envio e chega numa mensagem do sistema' : 'sai na lista depois da sua mensagem'
    "#{nome} fez proposta: o preço dela #{onde}."
  end

  # Sem categoria do motivo, o modelo só pode dizer que a seguradora não fez proposta.
  def sem_proposta(nome, categoria)
    "#{nome} não fez proposta nesta cotação. #{MOTIVOS.fetch(categoria, SEM_MOTIVO)}"
  end

  def conferencia(motivo, texto)
    ::Autonomia::Agents::Tools::Native::Conferencia.new(texto: texto, motivo: motivo)
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
