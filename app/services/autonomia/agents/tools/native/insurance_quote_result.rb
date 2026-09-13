# A LIA VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420).
#
# Ferramenta ASSÍNCRONA de exibição, do principal. Lê o que a cotação mais nova da conversa guardou por
# seguradora (`Insurance::ResultadoDaCotacao`) e não chama o portal.
#
#   - Com preço a mostrar: `precheck` devolve nil e a execução é aberta. O modelo recebe `aceite` e fala;
#     a segunda passada do motor publica os itens (`poll`), escritos por `QuoteOffers.item`, e o
#     publicador os adia enquanto a entrega da fala do turno está em curso.
#   - Sem preço a mostrar: `precheck` devolve o texto ao modelo e nenhuma execução é aberta.
#
# O texto ao modelo não tem valor de prêmio. Tem o nome da seguradora perguntada, o desfecho dela e, só
# quando `Insurance::MotivoDaRecusa` libera, o texto do portal.
#
# Os cinco textos de classe que o motor e o encerramento publicam sem instância são vazios: o publicador
# devolve `skipped` para texto vazio, sem criar mensagem (`AsyncPublisher#texto_de`).
class Autonomia::Agents::Tools::Native::InsuranceQuoteResult < Autonomia::Agents::Tools::Native::Base
  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora

  # O motivo com que `Bound#recusar_pela_conferencia` registra a resposta dada no turno.
  RESPONDIDO_NO_TURNO = 'resultado_respondido_no_turno'.freeze
  # No handle desta execução: o id da execução de `cotar_seguro` lida no `start`, e os códigos a publicar.
  EXECUCAO_KEY = 'execucao_da_cotacao'.freeze
  CODIGOS_KEY = 'seguradoras'.freeze

  # Os textos ao modelo.
  SEM_COTACAO = 'Não há cotação nesta conversa para mostrar. Não invente preço nem seguradora.'.freeze
  SEM_RESULTADO = 'O resultado da cotação desta conversa não ficou guardado para consulta. Não invente preço ' \
                  'nem seguradora; se o cliente quiser ver os preços de novo, ofereça chamar um atendente.'.freeze
  SEM_PRECO_AINDA = 'A cotação ainda está correndo e nenhum preço chegou até agora. Não invente preço nem ' \
                    'seguradora.'.freeze
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

    # A lista só vira mensagem enquanto a execução lida no `start` for a cotação mais nova da conversa.
    def publicacao_vale?(run)
      execucao = run.handle.to_h[EXECUCAO_KEY]
      execucao.present? && Resultado.execucao_mais_nova(run.conversation_id)&.id == execucao.to_i
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

  # -> a execução de `cotar_seguro` lida agora e os códigos com preço a publicar.
  def start
    { EXECUCAO_KEY => resultado&.run&.id, CODIGOS_KEY => resposta.last }
  end

  # Publica os itens quando a execução lida no `start` ainda é a cotação mais nova da conversa.
  def poll(handle:, **)
    atual = resultado
    return progress_class.done unless atual && atual.run.id == handle.to_h[EXECUCAO_KEY].to_i

    progress_class.done(deliveries: [atual.itens(handle.to_h[CODIGOS_KEY])].compact)
  end

  private

  def resultado
    return @resultado if defined?(@resultado)

    @resultado = Resultado.da_conversa(run&.conversation_id || delivery&.conversation&.id)
  end

  def seguradora
    params['seguradora'].to_s.strip.presence
  end

  # -> [texto ao modelo, códigos com preço a publicar], calculado uma vez por instância.
  def resposta
    @resposta ||= montar_resposta
  end

  # A execução que não gravou resultado conta como "ainda sem preço" enquanto corre: a linha em voo no
  # deploy grava o resultado na consulta seguinte.
  def montar_resposta
    return [SEM_COTACAO, []] if resultado.nil?
    return [SEM_RESULTADO, []] unless resultado.guardado? || resultado.correndo?

    seguradora ? por_seguradora : geral
  end

  def geral
    codigos = resultado.com_preco
    return [resultado.correndo? ? SEM_PRECO_AINDA : SEM_PRECO, []] if codigos.empty?

    partes = [LISTA_DEPOIS, (AINDA_CORRENDO if resultado.correndo?), (HA_SEM_PROPOSTA if resultado.sem_proposta?),
              (SEM_BONUS if resultado.sem_bonus?)]
    [partes.compact.join("\n"), codigos]
  end

  def por_seguradora
    codigos = resultado.procurar(seguradora)
    return [resultado.correndo? ? NAO_ENCONTRADA_AINDA : NAO_ENCONTRADA, []] if codigos.empty?

    com_preco = resultado.com_preco(codigos)
    partes = codigos.map { |codigo| fala(codigo) }
    partes = [LISTA_DEPOIS, *partes, (SEM_BONUS if resultado.sem_bonus?)] if com_preco.any?
    [partes.compact.join("\n"), com_preco]
  end

  # O que o modelo lê sobre UMA seguradora.
  def fala(codigo)
    nome = resultado.nome(codigo)
    case resultado.desfecho(codigo)
    when Guardado::COM_PRECO then "#{nome} fez proposta: o preço dela sai na lista depois da sua mensagem."
    when Guardado::AGUARDANDO then "#{nome} ainda não respondeu, e a cotação continua correndo."
    else sem_proposta(nome, resultado.motivo(codigo))
    end
  end

  # Sem motivo liberado pela regra, o modelo só pode dizer que a seguradora não fez proposta.
  def sem_proposta(nome, motivo)
    return "#{nome} não fez proposta nesta cotação. #{SEM_MOTIVO}" if motivo.nil?

    "#{nome} não fez proposta nesta cotação. A seguradora deu este motivo, para você explicar com as suas " \
      "palavras, sem copiar o texto: \"#{motivo}\""
  end

  def conferencia(motivo, texto)
    ::Autonomia::Agents::Tools::Native::Conferencia.new(texto: texto, motivo: motivo)
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
