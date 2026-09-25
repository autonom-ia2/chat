# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8b do Agente de Cotação, #459).
#
# Quando o cliente diz "me manda a da Porto", o que ele quer é o PDF daquela seguradora, não o comparativo. O
# adapter gera esse PDF (`quote/proposal` com `insurerCode`: 1 página, só ela, ~5 s, medido em 18/09/2026); até
# aqui o único chamador (o comparativo) nunca passava o código.
#
# Ferramenta SÍNCRONA do principal, no molde de `ver_resultado_da_cotacao`: acha a cotação mais nova da conversa
# (`Insurance::ResultadoDaCotacao`), acha a seguradora que o MODELO escolheu na lista fechada da cotação
# (`#codigo_do_nome`, chat#718: o nome inteiro, e nunca um casamento de palavras) e, para quem fez proposta, pede o PDF
# ao portal e o publica na conversa. Nome fora da lista volta com a lista, para ele escolher ou perguntar. Nunca abre
# cotação: duas seguradoras são duas chamadas sobre a mesma cotação.
#
# QUEM ESCREVE AO CLIENTE É A LIA (decisão do CEO). O arquivo sai SEM LEGENDA e ao modelo volta só o que
# aconteceu, sem valor nenhum; a frase que acompanha o arquivo é dela.
#
# O ARQUIVO SAI PELO PUBLICADOR DA COTAÇÃO (`AsyncPublisher`, com a execução de `cotar_seguro` da conversa): o
# mesmo download pelo `SafeFetch`, a mesma gravação antes da mensagem, a mesma autorização reconferida sob o
# lock e a nota privada quando há responsável. `publish!` não espera a cadeia do turno em que a cotação nasceu, e
# a entrega nunca é adiada. A URL do portal não tem autenticação e leva o nome do segurado: ela só vai ao
# download, nunca ao modelo, ao cliente nem ao log.
#
# SESSÃO SÓ A QUE JÁ ESTÁ VIVA (`with_live_session`), como a `consultar_placa`: abrir sessão é login de até
# 60 s, e o turno não espera isso. Sem ela, "não deu agora".
class Autonomia::Agents::Tools::Native::InsuranceQuoteProposal < Autonomia::Agents::Tools::Native::Base
  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora
  Arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo

  # O mesmo código de recusa sem contexto de entrega da `ver_resultado_da_cotacao` (`Tools::Recusa::MOTIVOS`).
  SEM_CONTEXTO = 'lista_indisponivel_nesta_superficie'.freeze
  NOME = 'Proposta'.freeze

  # Os textos ao modelo. Nenhum vai ao cliente, e nenhum leva valor.
  SEM_COTACAO = 'Não há cotação nesta conversa com proposta para enviar. Não abra cotação nova por causa deste ' \
                'pedido e não invente seguradora.'.freeze
  SEM_PRECO = 'Nenhuma seguradora fez proposta nesta cotação, e não há proposta para enviar.'.freeze
  # A LISTA FECHADA (chat#718): quando o nome não é exatamente o de uma seguradora com proposta, o modelo recebe os
  # nomes e escolhe; se o cliente não nomeou nenhuma delas, a saída é perguntar.
  QUAL = 'A seguradora pedida não é, pelo nome exato, uma das que fizeram proposta nesta cotação. Fizeram proposta: ' \
         '%<nomes>s. ' \
         'Se o cliente pediu uma delas, chame de novo com seguradora igual ao nome dela, escrito exatamente como está ' \
         'aqui. Se ele não nomeou nenhuma delas, não chame de novo: pergunte a ele qual quer.'.freeze
  # Com a cotação correndo: as que já fizeram proposta, para o nome escrito diferente não virar "ainda não apareceu".
  JA_FIZERAM = 'Já fizeram proposta até agora: %<nomes>s. Se o cliente pediu uma delas, chame de novo com seguradora ' \
               'igual ao nome dela, escrito exatamente como está aqui.'.freeze
  ENVIADA = 'A proposta da %<nome>s foi enviada ao cliente nesta conversa, como arquivo PDF. Escreva você a ' \
            'mensagem que acompanha o arquivo, sem link e sem travessão.'.freeze
  SEM_PROPOSTA = '%<nome>s não fez proposta nesta cotação, e não há proposta dela para enviar. Nada foi enviado ao ' \
                 'cliente.'.freeze
  AINDA_NAO = '%<nome>s ainda não respondeu, e a cotação continua correndo. Nada foi enviado ao cliente.'.freeze
  # A COTAÇÃO CORRENDO E O NOME AINDA SEM RESULTADO: a seguradora pode não ter respondido, então nem "nenhuma fez
  # proposta" nem a lista de quem já fez (que daria a entender que a pedida não fez). Achado da revisão da PR #460.
  AINDA_CORRENDO = 'A cotação ainda está correndo e essa seguradora não apareceu no resultado até agora. Nada foi ' \
                   'enviado ao cliente: o comparativo chega quando a cotação terminar.'.freeze
  FALHOU = 'Não deu para gerar a proposta da %<nome>s agora. Nada foi enviado ao cliente: não mande link nem ' \
           'invente valor.'.freeze
  # A NOTA À EQUIPE NA HORA (decisão 3 do Rodrigo, 25/09/2026, chat#718): a proposta que não sai ia só ao log e ao
  # modelo. Agora quem atende sabe, por mensagem privada (`Insurance::NotaNaHora`), qual seguradora e por quê.
  NOTA = 'A proposta em PDF da %<nome>s não saiu agora: %<motivo>s. A pessoa pediu essa proposta e ouviu da IA que ' \
         'não deu para gerar agora; confira no portal e mande a proposta, se for o caso.'.freeze
  MOTIVOS_DA_NOTA = { 'sem_url' => 'o portal não devolveu o arquivo (ou não havia sessão aberta com ele)',
                      'nao_publicada' => 'o arquivo não pôde ser baixado ou publicado na conversa' }.freeze
  MOTIVO_DO_PORTAL = 'o portal respondeu com erro'.freeze

  class << self
    def slug
      'enviar_proposta_da_seguradora'
    end

    def tool_name
      'Enviar proposta da seguradora'
    end

    def description
      'Envia ao cliente, como arquivo PDF nesta conversa, a proposta de UMA seguradora da cotação desta conversa, ' \
        'sem cotar de novo. Use quando o cliente escolher uma seguradora e pedir a proposta ou o PDF dela. Uma ' \
        'seguradora por chamada: se ele pedir duas, chame duas vezes. Devolve o que aconteceu, para você escrever ' \
        'a mensagem ao cliente.'
    end

    def params
      [{ 'name' => 'seguradora', 'type' => 'string', 'required' => false,
         'description' => 'O nome da seguradora que o cliente escolheu, escrito exatamente como a cotação o escreve (como ' \
                          'veio do especialista ou do comparativo). null quando o cliente não nomeou nenhuma seguradora ' \
                          'desta cotação.' },
       Resultado::PARAM_PRODUTO]
    end

    # Pede o PDF ao portal: exige o módulo de seguros e a conexão pronta, como a cotação.
    def available_for?(agent)
      ::Autonomia::Agents::Tools::Native::InsuranceQuote.available_for?(agent)
    end
  end

  # -> o texto ao modelo.
  def call
    conversa = delivery&.conversation
    return error(SEM_CONTEXTO) if conversa.nil?

    escolha = Resultado.escolha(conversa.id, params, especialista, exigir: true)
    return escolha.pergunta if escolha.pergunta

    @resultado = Resultado.da_conversa(conversa.id, faixa: escolha.faixa)
    return SEM_COTACAO if @resultado.nil?

    codigo = @resultado.codigo_do_nome(params['seguradora'])
    return qual if codigo.nil?

    responder(codigo)
  end

  private

  def qual
    nomes = @resultado.com_preco.map { |codigo| @resultado.nome(codigo) }.join('; ')
    return [AINDA_CORRENDO, (format(JA_FIZERAM, nomes: nomes) if nomes.present?)].compact.join(' ') if @resultado.correndo?

    nomes.empty? ? SEM_PRECO : format(QUAL, nomes: nomes)
  end

  def responder(codigo)
    nome = @resultado.nome(codigo)
    case @resultado.desfecho(codigo)
    when Guardado::COM_PRECO then enviar(codigo, nome)
    when Guardado::AGUARDANDO then format(AINDA_NAO, nome: nome)
    else format(SEM_PROPOSTA, nome: nome)
    end
  end

  # Pede o PDF daquela seguradora e o publica. O adapter que recusa (`validation`: "no quoted insurer to print")
  # diz que ela não fez proposta; qualquer outra falha é "não deu agora", com a CLASSE do erro no log (a mensagem
  # pode levar a URL).
  #
  # Sem sessão viva ou sem URL https, o motivo vai ao log como código curto; o download que falha, o publicador já
  # registra com o motivo dele (`arquivo indisponivel`).
  def enviar(codigo, nome)
    url = url_da_proposta(codigo)
    return falhou(nome, 'sem_url') unless url.to_s.match?(Arquivo::URL_SEGURA)
    return falhou(nome, 'nao_publicada') unless publicar(url, nome).published?

    format(ENVIADA, nome: nome)
  rescue ::Autonomia::Insurance::Connector::Error => e
    return format(SEM_PROPOSTA, nome: nome) if e.kind == :validation

    falhou(nome, e.class.name)
  rescue StandardError => e
    falhou(nome, e.class.name)
  end

  def url_da_proposta(codigo)
    proposta = sessions.with_live_session do |sessao|
      connector.quote_proposal(provider: connection.provider, session: sessao, quote_id: run_da_cotacao.handle['quote_id'],
                               insurer_code: codigo)
    end
    proposta.to_h['url'].presence
  end

  # SEM LEGENDA, como todo arquivo do motor desde a PR C: a frase é da Lia. O publicador baixa, grava e anexa; o
  # download que falha não publica nada.
  def publicar(url, nome)
    arquivo = Arquivo.new(url: url, nome: nome_do_arquivo(nome))
    ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run_da_cotacao).publish!(arquivo)
  end

  def falhou(nome, motivo)
    Rails.logger.warn("[autonomia][insurance] proposta da seguradora falhou account=#{account.id} #{motivo}")
    nota_da_falha(nome, motivo)
    format(FALHOU, nome: nome)
  end

  # Uma nota por seguradora e turno: o modelo que tenta de novo no mesmo turno não duplica a nota.
  def nota_da_falha(nome, motivo)
    texto = format(NOTA, nome: nome, motivo: MOTIVOS_DA_NOTA.fetch(motivo, MOTIVO_DO_PORTAL))
    ::Autonomia::Insurance::NotaNaHora.postar(delivery&.conversation, texto,
                                              chave: "proposta:#{delivery&.origin_message_id}:#{nome}")
  end

  # "Proposta Usebens, placa HIK9383.pdf", no molde do comparativo (`InsuranceQuote::Comparativo#nome_do_comparativo`):
  # vírgula, e não travessão nem dois pontos; sem placa, o ramo. O nome da seguradora vem do portal: barra e dois
  # pontos saem, porque o sistema do cliente os recusa em nome de arquivo.
  def nome_do_arquivo(nome)
    argumentos = run_da_cotacao.arguments.to_h
    placa = argumentos.dig('vehicle', 'plate').to_s.upcase.gsub(/[^A-Z0-9]/, '')
    sufixo = placa.present? ? "placa #{placa}" : (argumentos['produto'].presence || 'auto').to_s.tr('_', ' ')
    "#{NOME} #{nome.to_s.gsub(%r{[/\\:]}, ' ').squish}, #{sufixo}.pdf"
  end

  def run_da_cotacao
    @resultado.run
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(account).find(&:ready?) ||
                    raise(::Autonomia::Insurance::Connector::Error.new(:config, 'sem conexão pronta'))
  end

  def sessions
    @sessions ||= ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  def connector
    @connector ||= ::Autonomia::Insurance::Connector.client
  end
end
