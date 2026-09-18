# A LIA VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420; desenho da rodada 8).
#
# Ferramenta SÍNCRONA do principal. Lê, no instante da pergunta, o que a cotação mais nova da conversa guardou
# por seguradora (`Insurance::ResultadoDaCotacao`), e não chama o portal.
#
#   - Com preço a mostrar, a lista é escrita pelo código (`QuoteOffers.item`) e ANEXADA ao turno
#     (`Tools::Delivery#anexar`): o `Operate::Responder` a entrega logo depois da fala da Lia, na mesma entrega.
#   - O modelo recebe só estado: quantas seguradoras fizeram proposta, se a lista vai anexada e, quando o cliente
#     perguntou por uma seguradora, o nome, o desfecho e a categoria do motivo (`veiculo`, `regiao` ou nenhuma).
#     Nunca valor, nunca texto do portal.
#
# Nada de execução, de fila ou de lista de outro turno: cada pergunta mostra o que está guardado agora, e a mesma
# pergunta feita duas vezes recebe a lista duas vezes. Duas chamadas no MESMO turno anexam uma lista só, com as
# seguradoras das duas (a chave do anexo é a mesma).
#
# Sem contexto de entrega (Testar, Copiloto, playground) não há conversa para ler nem turno para receber a lista:
# erro nomeado, pelo registro de recusa.
class Autonomia::Agents::Tools::Native::InsuranceQuoteResult < Autonomia::Agents::Tools::Native::Base
  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora
  Motivo = ::Autonomia::Insurance::MotivoDaRecusa

  # A chave do anexo desta ferramenta no turno.
  ANEXO = 'lista_de_precos'.freeze
  # O código da recusa sem contexto de entrega (`Tools::Recusa::MOTIVOS`).
  SEM_CONTEXTO = 'lista_indisponivel_nesta_superficie'.freeze

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
  SEM_PRECO = 'Nenhuma seguradora fez proposta nesta cotação. Não invente preço nem seguradora.'.freeze
  NAO_ENCONTRADA = 'Nenhuma seguradora com esse nome está nesta cotação. Não liste as seguradoras: pergunte ao ' \
                   'cliente de qual ele fala.'.freeze
  NAO_ENCONTRADA_AINDA = 'Nenhuma seguradora com esse nome apareceu nesta cotação até agora, e ela ainda está ' \
                         'correndo. Não liste as seguradoras.'.freeze
  LISTA_ANEXADA = 'A lista com os preços vai anexada à sua resposta e chega logo depois da sua mensagem, escrita ' \
                  'pelo sistema. Na sua mensagem, apresente a lista com as suas palavras, sem escrever valor, sem ' \
                  'listar seguradoras e sem travessão.'.freeze
  AINDA_CORRENDO = 'A cotação ainda está correndo: podem chegar mais preços.'.freeze
  HA_SEM_PROPOSTA = 'Algumas seguradoras não fizeram proposta: só fale delas se o cliente perguntar.'.freeze
  SEM_BONUS = 'Esta cotação foi feita sem a classe de bônus da apólice atual.'.freeze
  # O motivo de quem não fez proposta, por categoria (`Insurance::MotivoDaRecusa`). Nunca o texto do portal.
  MOTIVOS = {
    Motivo::VEICULO => 'Categoria do motivo: veiculo. A recusa foi pelo veículo cotado, e não se sabe qual ' \
                       'característica: conte com as suas palavras que ela não aceitou o veículo, sem acrescentar detalhe.',
    Motivo::REGIAO => 'Categoria do motivo: regiao. A recusa foi pela região, e não se sabe mais que isso: conte com ' \
                      'as suas palavras que ela não atende a região, sem acrescentar detalhe.'
  }.freeze
  SEM_MOTIVO = 'Categoria do motivo: nenhuma. Não há motivo que você possa contar: diga só que ela não fez proposta.'.freeze

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
        'ou perguntar se uma seguradora fez proposta. Os preços vão numa lista escrita pelo sistema, anexada à sua resposta.'
    end

    def params
      [{ 'name' => 'seguradora', 'type' => 'string', 'required' => false,
         'description' => 'Nome da seguradora que o cliente perguntou, como ele escreveu. Mais de uma: todos ' \
                          'os nomes neste mesmo campo. null para o resultado inteiro.' }]
    end

    # Sem o módulo de seguros ligado não há cotação a consultar. Não exige conexão pronta: lê o banco.
    def available_for?(agent)
      ::Autonomia::Insurance::Config.enabled?(agent.account)
    rescue StandardError
      false
    end
  end

  # -> o texto ao modelo. Com preço a mostrar, anexa a lista ao turno antes de devolver.
  def call
    conversa = delivery&.conversation
    return ::Autonomia::Agents::Tools::Recusa.para_modelo(SEM_CONTEXTO, slug: self.class.slug, delivery: delivery, agente: agent) if conversa.nil?

    texto, codigos = resposta(conversa)
    anexar(codigos) if codigos.any?
    texto
  end

  private

  def seguradora
    params['seguradora'].to_s.strip.presence
  end

  # -> [texto ao modelo, códigos com preço a anexar].
  def resposta(conversa)
    @resultado = Resultado.da_conversa(conversa.id)
    return [SEM_COTACAO, []] if @resultado.nil?

    sem_leitura = texto_sem_leitura
    return [sem_leitura, []] if sem_leitura

    seguradora ? por_seguradora : geral
  end

  # A lista do turno: os códigos desta chamada somados aos que uma chamada anterior do mesmo turno já anexou.
  def anexar(codigos)
    todos = (Array(delivery.anexo(ANEXO)&.dados) + codigos).uniq
    delivery.anexar(ANEXO, @resultado.itens(todos), dados: todos)
  end

  # -> o texto de quando a cotação encerrada não tem resultado a ler, ou nil. A que ainda corre sem ter gravado
  # resultado (a linha em voo no deploy, ou a que nem consultou o portal) tem: "ainda sem preço". A encerrada
  # com envio incerto pode existir no portal; a encerrada sem número do portal não chegou às seguradoras; a
  # encerrada antes desta versão não guardou o resultado.
  def texto_sem_leitura
    return nil if @resultado.correndo?
    return ENVIO_INCERTO if @resultado.envio_incerto?
    return NAO_CHEGOU unless @resultado.cotou?

    SEM_RESULTADO unless @resultado.guardado?
  end

  def geral
    todos = @resultado.com_preco
    return [@resultado.correndo? ? SEM_PRECO_AINDA : SEM_PRECO, []] if todos.empty?

    [avisos_do_geral(todos.size).join("\n"), todos]
  end

  def avisos_do_geral(total)
    [contagem(total), LISTA_ANEXADA, (AINDA_CORRENDO if @resultado.correndo?),
     (HA_SEM_PROPOSTA if @resultado.sem_proposta?), (SEM_BONUS if @resultado.sem_bonus?)].compact
  end

  def por_seguradora
    codigos = @resultado.procurar(seguradora)
    return [@resultado.correndo? ? NAO_ENCONTRADA_AINDA : NAO_ENCONTRADA, []] if codigos.empty?

    com_preco = @resultado.com_preco(codigos)
    partes = [contagem(@resultado.com_preco.size), (LISTA_ANEXADA if com_preco.any?), *codigos.map { |codigo| fala(codigo) },
              (SEM_BONUS if com_preco.any? && @resultado.sem_bonus?)]
    [partes.compact.join("\n"), com_preco]
  end

  # Quantas seguradoras fizeram proposta, sem nome e sem valor.
  def contagem(total)
    quando = @resultado.correndo? ? 'até agora' : 'nesta cotação'
    return "Nenhuma seguradora fez proposta #{quando}." if total.zero?

    "#{total} #{total == 1 ? 'seguradora fez' : 'seguradoras fizeram'} proposta #{quando}."
  end

  # O que o modelo lê sobre UMA seguradora.
  def fala(codigo)
    nome = @resultado.nome(codigo)
    case @resultado.desfecho(codigo)
    when Guardado::COM_PRECO then "#{nome} fez proposta: o preço dela vai na lista anexada."
    when Guardado::AGUARDANDO then "#{nome} ainda não respondeu, e a cotação continua correndo."
    else "#{nome} não fez proposta nesta cotação. #{MOTIVOS.fetch(@resultado.motivo(codigo), SEM_MOTIVO)}"
    end
  end
end
