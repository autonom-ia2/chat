# A rodada diária da leitura automática do painel de desempenho de UM agente (#2301): lê com a IA as conversas que
# ganharam mensagem desde a última leitura e regrava as procuras delas.
#
#   Autonomia::Desempenho::LeituraAutomatica::Orquestrador.new(ficha).call
#
# - Liga com três coisas: a ENV AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA (desligada por padrão), a flag da conta
#   `agentes_painel_desempenho` e a ficha vigente com `chave_de_leitura` (o job confere as duas primeiras).
# - Quem paga é o cliente: só lê com a chave de IA da própria conta (app `crm_kanban_ai`). Sem ela (ou com a chave da
#   instalação), a rodada fica `sem_ia`, sem nenhuma chamada, e a tela diz isso.
# - Uma rodada por agente de cada vez (trava no Redis). No máximo MAX_CONVERSAS por rodada, as que esperam há mais
#   tempo primeiro; passou do teto diário de gasto, a rodada para como `teto` e o resto fica para a próxima.
# - Conversa recusada (falha da chamada, resposta fora do catálogo) mantém as procuras de antes; na segunda falha
#   seguida, fica como não lida até ganhar mensagem nova.
class Autonomia::Desempenho::LeituraAutomatica::Orquestrador
  ENV_LIGADA = 'AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA'.freeze
  MAX_CONVERSAS = 500
  FALHAS_PARA_DESISTIR = 2
  TRAVA_POR = 6.hours
  FALHAS_POR = 7.days
  # Agente sem carga (nenhuma leitura guardada): a primeira rodada começa nos últimos 30 dias.
  SEM_CARGA = 30.days
  ROTULO_PADRAO = 'AGENTE'.freeze

  def self.ligada?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENV_LIGADA, false)) || false
  end

  def initialize(ficha)
    @ficha = ficha
    @account = ficha.account
  end

  # A rodada gravada, ou nil quando outra rodada do mesmo agente está em andamento.
  def call
    token = SecureRandom.hex(8)
    return unless Redis::Alfred.set(chave('trava'), token, nx: true, ex: TRAVA_POR.to_i)

    begin
      rodar
    ensure
      Redis::Alfred.delete_if_equals(chave('trava'), token)
    end
  end

  private

  def rodar
    @rodada = abrir_rodada
    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    return fechar('sem_ia', pendentes: candidatas.size) unless credencial&.dig(:source) == :hook

    ler_todas(credencial)
  rescue StandardError => e
    # Só a classe: a mensagem pode trazer texto da conversa.
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} ficha=#{@ficha.id} erro=#{e.class.name}")
    @rodada&.update!(status: 'erro', terminada_em: Time.current)
    @rodada
  end

  def abrir_rodada
    corte = Time.current
    Autonomia::Desempenho::Rodada.create!(sujeito.merge(corte_em: corte, piso_em: piso(corte), iniciada_em: corte, status: 'rodando',
                                                        lote: Autonomia::Desempenho::LeituraAutomatica::Gravacao::LOTE))
  end

  # O piso da primeira rodada é a última mensagem que a carga leu; as seguintes repetem o mesmo.
  def piso(corte)
    anterior = Autonomia::Desempenho::Rodada.do_sujeito(@account, @ficha.sujeito_type, @ficha.sujeito_id).recentes.pick(:piso_em)
    anterior || leituras.maximum(:lida_ate_em) || (corte - SEM_CARGA)
  end

  def ler_todas(credencial)
    leitor = Autonomia::Desempenho::LeituraAutomatica::Leitor.new(account: @account, ficha: @ficha, credencial: credencial)
    lidas = 0
    candidatas.first(MAX_CONVERSAS).each do |conversation_id|
      return fechar('teto', lidas: lidas, pendentes: candidatas.size - lidas) if teto.passou?

      lidas += 1 if ler(leitor, conversation_id)
    end
    fechar('ok', lidas: lidas, pendentes: candidatas.size - lidas)
  end

  # true quando a conversa saiu da fila (lida ou desistida); false quando fica para a próxima rodada.
  def ler(leitor, conversation_id)
    conversa = @account.conversations.find(conversation_id)
    mensagens = conversa.messages.where(created_at: ..@rodada.corte_em).reorder(:created_at, :id).to_a
    gravacao = Autonomia::Desempenho::LeituraAutomatica::Gravacao.new(ficha: @ficha, conversa: conversa, mensagens: mensagens, esquema: esquema)
    texto = transcricao(conversa, mensagens)
    if texto.size > teto.max_caracteres
      gravacao.nao_lida!
      return true
    end

    gravacao.gravar!(esquema.procuras(leitor.ler(texto, esquema.json)))
    Redis::Alfred.delete(chave("falhas:#{conversation_id}"))
    true
  rescue Autonomia::Desempenho::LeituraAutomatica::Leitor::Falha, Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida => e
    falhou(gravacao, conversation_id, e)
  end

  def falhou(gravacao, conversation_id, erro)
    Rails.logger.warn("[desempenho][leitura] conta=#{@account.id} conversa=#{conversation_id} falha=#{erro.class.name}")
    vezes = Redis::Alfred.incr(chave("falhas:#{conversation_id}"))
    Redis::Alfred.expire(chave("falhas:#{conversation_id}"), FALHAS_POR.to_i)
    return false if vezes.to_i < FALHAS_PARA_DESISTIR

    Redis::Alfred.delete(chave("falhas:#{conversation_id}"))
    gravacao.nao_lida!
    true
  end

  def fechar(status, lidas: 0, pendentes: 0)
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
