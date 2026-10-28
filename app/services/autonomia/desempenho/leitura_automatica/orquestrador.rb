# A rodada diária da leitura automática do painel de desempenho de UM agente (#2301): lê com a IA as conversas que
# ganharam mensagem desde a última leitura e regrava as procuras delas.
#
#   Autonomia::Desempenho::LeituraAutomatica::Orquestrador.new(ficha).call
#
# - Liga com três coisas: a ENV AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA (desligada por padrão), a flag da conta
#   `agentes_painel_desempenho` e a ficha vigente com `chave_de_leitura` (o job confere as duas primeiras).
# - Quem paga é o cliente: só lê com a chave de IA da própria conta (app `crm_kanban_ai`). Sem ela (ou com a chave da
#   instalação), a rodada fica `sem_ia`, sem nenhuma chamada, e a tela diz isso.
# - Ficha com catálogo ou faixas quebrados: a rodada fecha `erro` antes da primeira chamada, sem gastar nada.
# - Uma rodada por agente de cada vez (trava no Redis, renovada a cada conversa). No máximo MAX_CONVERSAS por rodada, as
#   que esperam há mais tempo primeiro; passou do teto diário de gasto, a rodada para como `teto` e o resto fica para a
#   próxima.
# - Erro permanente da chamada (chave recusada, modelo inexistente, pedido inválido) fecha a rodada na hora: `sem_ia`
#   no 401, `erro` no resto. Erro passageiro (rede, 429, 5xx) conta para a conversa; o terceiro seguido fecha `erro`.
# - Conversa recusada (resposta fora do catálogo, JSON quebrado, qualquer exceção depois da chamada) mantém as
#   procuras de antes; na segunda falha seguida, fica como não lida até ganhar mensagem nova.
# - Rodada `ok` sem pendentes: a próxima só procura mensagem depois do corte dela (o piso anda).
class Autonomia::Desempenho::LeituraAutomatica::Orquestrador
  # Fecha a rodada no meio, com o status dado.
  class Parada < StandardError
    attr_reader :status

    def initialize(status)
      @status = status
      super("rodada_#{status}")
    end
  end

  ENV_LIGADA = 'AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA'.freeze
  MAX_CONVERSAS = 500
  FALHAS_PARA_DESISTIR = 2
  PASSAGEIRAS_PARA_PARAR = 3
  TRAVA_POR = 6.hours
  FALHAS_POR = 7.days
  # Agente sem carga (nenhuma leitura guardada): a primeira rodada começa nos últimos 30 dias.
  SEM_CARGA = 30.days
  ROTULO_PADRAO = 'AGENTE'.freeze
  CHAVE_RECUSADA = 401

  def self.ligada?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENV_LIGADA, false)) || false
  end

  def initialize(ficha)
    @ficha = ficha
    @account = ficha.account
  end

  # A rodada gravada, ou nil quando outra rodada do mesmo agente está em andamento.
  def call
    @token = SecureRandom.hex(8)
    return unless Redis::Alfred.set(chave('trava'), @token, nx: true, ex: TRAVA_POR.to_i)

    begin
      rodar
    ensure
      Redis::Alfred.delete_if_equals(chave('trava'), @token)
    end
  end

  private

  # Erro inesperado fora de uma conversa: a rodada fica `erro` e a exceção sobe (o job descarta, sem nova tentativa).
  def rodar
    @rodada = abrir_rodada
    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    return fechar('sem_ia') unless credencial&.dig(:source) == :hook

    problemas = Autonomia::Desempenho::LeituraAutomatica::ConferenciaDaFicha.new(@ficha).problemas
    return ficha_quebrada(problemas) if problemas.any?

    ler_todas(credencial)
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} ficha=#{@ficha.id} erro=#{e.class.name}")
    @rodada&.update!(status: 'erro', terminada_em: Time.current)
    raise
  end

  def ficha_quebrada(problemas)
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} ficha=#{@ficha.id} ficha_quebrada=#{problemas.join(',')}")
    fechar('erro')
  end

  def abrir_rodada
    corte = Time.current
    Autonomia::Desempenho::Rodada.create!(sujeito.merge(corte_em: corte, piso_em: piso(corte), iniciada_em: corte, status: 'rodando',
                                                        lote: Autonomia::Desempenho::LeituraAutomatica::Gravacao::LOTE))
  end

  # O piso da primeira rodada é a última mensagem que a carga leu. Depois de uma rodada `ok` sem pendentes, é o corte
  # dela (nada antes disso ficou por ler); senão, repete o piso da anterior, para a pendente não sumir da fila.
  def piso(corte)
    anterior = Autonomia::Desempenho::Rodada.do_sujeito(@account, @ficha.sujeito_type, @ficha.sujeito_id).recentes
                                            .where.not(status: 'rodando').first
    return anterior.corte_em if anterior&.status == 'ok' && anterior.conversas_pendentes.zero?

    anterior&.piso_em || leituras.maximum(:lida_ate_em) || (corte - SEM_CARGA)
  end

  def ler_todas(credencial)
    leitor = Autonomia::Desempenho::LeituraAutomatica::Leitor.new(account: @account, ficha: @ficha, credencial: credencial)
    @lidas = @puladas = @passageiras = 0
    candidatas.first(MAX_CONVERSAS).each do |conversation_id|
      return fechar('teto') if teto.passou?

      Redis::Alfred.expire(chave('trava'), TRAVA_POR.to_i)
      contar(ler(leitor, conversation_id))
    end
    fechar('ok')
  rescue Parada => e
    fechar(e.status)
  end

  # :lida (saiu da fila, lida ou desistida), :pendente (fica para a próxima) ou :pulada (a conversa sumiu).
  def contar(resultado)
    @lidas += 1 if resultado == :lida
    @puladas += 1 if resultado == :pulada
  end

  def ler(leitor, conversation_id)
    conversa = @account.conversations.find_by(id: conversation_id)
    return :pulada if conversa.nil?

    mensagens = conversa.messages.where(created_at: ..@rodada.corte_em).reorder(:created_at, :id).to_a
    gravacao = Autonomia::Desempenho::LeituraAutomatica::Gravacao.new(ficha: @ficha, conversa: conversa, mensagens: mensagens, esquema: esquema)
    ler_e_gravar(leitor, conversa, mensagens, gravacao)
  end

  def ler_e_gravar(leitor, conversa, mensagens, gravacao)
    texto = transcricao(conversa, mensagens)
    if texto.size > teto.max_caracteres
      gravacao.nao_lida!
      return :lida
    end

    gravacao.gravar!(esquema.procuras(chamar(leitor, texto)))
    Redis::Alfred.delete(chave("falhas:#{conversa.id}"))
    :lida
  rescue Parada
    raise
  rescue StandardError => e
    # Erro passageiro da chamada e qualquer exceção depois dela são da conversa: não derrubam a rodada e, na segunda
    # vez seguida, a conversa sai da fila.
    falhou(gravacao, conversa.id, e)
  end

  # Erro permanente ou o terceiro passageiro seguido fecham a rodada (Parada); o passageiro sobe para a conversa.
  def chamar(leitor, texto)
    resposta = leitor.ler(texto, esquema.json)
    @passageiras = 0
    resposta
  rescue Crm::Ai::ResponsesClient::Error => e
    raise Parada, (e.status.to_i == CHAVE_RECUSADA ? 'sem_ia' : 'erro') if permanente?(e)

    @passageiras += 1
    raise Parada, 'erro' if @passageiras >= PASSAGEIRAS_PARA_PARAR

    raise
  end

  # 4xx que não é passageiro (401, 403, 404, 400, 422): não adianta tentar a próxima conversa. Sem status (resposta
  # vazia, já cobrada) é problema da conversa, não da conta. O 429 é passageiro aqui: a cota esgotada também volta 429,
  # e três seguidos fecham a rodada.
  def permanente?(erro) = erro.status.present? && !erro.passageira?

  def falhou(gravacao, conversation_id, erro)
    Rails.logger.warn("[desempenho][leitura] conta=#{@account.id} conversa=#{conversation_id} falha=#{erro.class.name}")
    vezes = Redis::Alfred.incr(chave("falhas:#{conversation_id}"))
    Redis::Alfred.expire(chave("falhas:#{conversation_id}"), FALHAS_POR.to_i)
    return :pendente if vezes.to_i < FALHAS_PARA_DESISTIR

    Redis::Alfred.delete(chave("falhas:#{conversation_id}"))
    gravacao.nao_lida!
    :lida
  end

  def fechar(status)
    lidas = @lidas.to_i
    pendentes = [candidatas.size - lidas - @puladas.to_i, 0].max
    @rodada.update!(status: status, terminada_em: Time.current, conversas_lidas: lidas, conversas_pendentes: pendentes,
                    custo_usd: custo)
    @rodada
  end

  # O gasto da rodada é o consumo gravado pela chamada desde que ela abriu (conta também a resposta que veio e foi
  # recusada). As rodadas da mesma conta rodam uma depois da outra, no mesmo job.
  def custo
    Crm::AiUsageEvent.for_account(@account.id).where(feature: Autonomia::Desempenho::LeituraAutomatica::Leitor::FEATURE)
                     .since(@rodada.iniciada_em).sum(:cost_estimate)
  end

  def transcricao(conversa, mensagens)
    Autonomia::Desempenho::LeituraAutomatica::Transcricao.new(conversa: conversa, mensagens: mensagens, remetentes: remetentes,
                                                              rotulo: rotulo).texto
  end

  # O rótulo de quem fala pelo agente na transcrição. A prova usou o primeiro nome do agente em maiúsculas (a chave de
  # leitura fala dele pelo nome); a ficha pode dar outro em `configuracao.leitura.rotulo_do_agente`.
  def rotulo
    @rotulo ||= @ficha.configuracao.dig('leitura', 'rotulo_do_agente').presence ||
                @ficha.configuracao.dig('meta', 'agente', 'nome').to_s.split.first&.upcase.presence || ROTULO_PADRAO
  end

  def candidatas
    @candidatas ||= Autonomia::Desempenho::LeituraAutomatica::Candidatas.new(
      **sujeito.except(:account_id), account: @account, remetentes: remetentes, piso: @rodada.piso_em, corte: @rodada.corte_em
    ).ids
  end

  def remetentes = @ficha.configuracao['remetentes_do_agente']
  def esquema = @esquema ||= Autonomia::Desempenho::LeituraAutomatica::Esquema.new(@ficha)
  def teto = @teto ||= Autonomia::Desempenho::LeituraAutomatica::Teto.new(account: @account, ficha: @ficha)
  def leituras = Autonomia::Desempenho::Leitura.do_sujeito(@account, @ficha.sujeito_type, @ficha.sujeito_id)
  def sujeito = { account_id: @account.id, sujeito_type: @ficha.sujeito_type, sujeito_id: @ficha.sujeito_id }
  def chave(parte) = "autonomia:desempenho:leitura:#{@account.id}:#{@ficha.sujeito_type}:#{@ficha.sujeito_id}:#{parte}"
end
