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
# - Uma rodada por CONTA de cada vez (trava no Redis, renovada a cada conversa): os agentes da mesma conta rodam em
#   fila, porque o teto diário de gasto é da conta e só é conferido antes de cada conversa. Com a trava ocupada, `call`
#   levanta ContaOcupada e o LeituraDaFichaJob se reagenda. No máximo MAX_CONVERSAS por rodada, as que esperam há mais
#   tempo primeiro; passou do teto diário, a rodada para como `teto` e o resto fica para a próxima.
# - Ao fechar com pendentes, grava `pendente_desde` (a mensagem pendente mais antiga): o painel mostra "Lido até" com
#   ela, sem refazer a consulta da fila.
# - Erro permanente da chamada (chave recusada, modelo inexistente, pedido inválido) fecha a rodada na hora:
#   `chave_recusada` no 401 e no 403, `erro` no resto. Erro passageiro (rede, tempo esgotado, 429, 5xx) deixa a conversa
#   pendente, sem contar falha dela; o terceiro seguido na rodada fecha `erro`. Só o tempo esgotado conta contra a
#   conversa, num contador próprio (VezesDaConversa) que a tira da fila, como não lida, quando se repete entre rodadas: a
#   conversa que estoura o tempo toda vez pagaria uma chamada por dia, sem o consumo entrar no teto. A OpenAI fora do ar
#   ou a cota esgotada (429, 5xx, rede) não é culpa da conversa e nunca a tira da fila.
# - Conversa recusada (resposta fora do catálogo, JSON quebrado) mantém as procuras de antes; na segunda falha seguida,
#   fica como não lida até ganhar mensagem nova.
# - Erro inesperado numa conversa (um bug na gravação, na transcrição) não é culpa dela: ela fica pendente, sem contar
#   falha, e o terceiro seguido na rodada fecha `erro` (o bug é do sistema, e cada conversa já pagou a chamada). Um
#   contador próprio por conversa (VezesDaConversa, separado do de falhas) tira da fila, como não lida, a conversa com
#   erro inesperado repetido entre rodadas: senão ela pagaria uma chamada por dia para sempre.
# - Rodada `ok` sem pendentes: a próxima só procura mensagem depois do corte dela, com uma margem (o piso anda).
# - Erro inesperado fora de uma conversa: a rodada fica `erro` e sobe RodadaComErro (o job descarta, sem nova tentativa).
#   Rodada interrompida no meio (deploy: o Sidekiq::Shutdown não é StandardError) também fecha `erro`, para não ficar
#   `rodando` para sempre.
class Autonomia::Desempenho::LeituraAutomatica::Orquestrador
  # Fecha a rodada no meio, com o status dado.
  class Parada < StandardError
    attr_reader :status

    def initialize(status)
      @status = status
      super("rodada_#{status}")
    end
  end

  # Outra rodada da mesma conta está em andamento.
  class ContaOcupada < StandardError; end

  # A rodada caiu e já ficou registrada como `erro` (a causa vai em `cause`).
  class RodadaComErro < StandardError; end

  ENV_LIGADA = 'AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA'.freeze
  MAX_CONVERSAS = 500
  PASSAGEIRAS_PARA_PARAR = 3
  INESPERADOS_PARA_PARAR = 3
  # O piso anda até o corte menos esta margem: mensagem gravada com o horário de origem (histórico do WhatsApp,
  # importação) pode chegar com `created_at` um pouco antes do corte da rodada que já passou. A margem só vale para a
  # conversa nunca lida: a que já tem leitura usa o próprio `lida_ate_em`, e mensagem retroativa anterior a ele não
  # entra na fila.
  MARGEM_DO_PISO = 1.hour
  TRAVA_POR = Autonomia::Desempenho::LeituraAutomatica::TravaDaConta::POR
  # Agente sem carga (nenhuma leitura guardada): a primeira rodada começa nos últimos 30 dias. A conversa nunca lida
  # também entra se tiver mensagem nesses 30 dias, mesmo antes do piso (Candidatas).
  SEM_CARGA = 30.days
  ROTULO_PADRAO = 'AGENTE'.freeze
  CHAVE_RECUSADA = [401, 403].freeze

  def self.ligada?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENV_LIGADA, false)) || false
  end

  def initialize(ficha)
    @ficha = ficha
    @account = ficha.account
  end

  # A rodada gravada. Levanta ContaOcupada, sem abrir rodada, quando outra rodada da mesma conta está em andamento.
  def call
    @trava = Autonomia::Desempenho::LeituraAutomatica::TravaDaConta.new(@account)
    raise ContaOcupada, "conta_#{@account.id}" unless @trava.pegar

    begin
      rodar
    ensure
      @rodada&.interrompida!
      @trava.soltar
    end
  end

  private

  # Erro inesperado fora de uma conversa: a rodada fica `erro` e sobe RodadaComErro (o job descarta, sem nova tentativa).
  # Sem rodada aberta (o erro foi ao abrir), a exceção sobe como veio: nada foi pago nem registrado.
  def rodar
    @rodada = abrir_rodada
    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    return fechar('sem_ia') unless credencial&.dig(:source) == :hook

    problemas = Autonomia::Desempenho::LeituraAutomatica::ConferenciaDaFicha.new(@ficha).problemas
    return ficha_quebrada(problemas) if problemas.any?

    ler_todas(credencial)
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} ficha=#{@ficha.id} erro=#{e.class.name}")
    raise if @rodada.nil?

    @rodada.update!(status: 'erro', terminada_em: Time.current)
    raise RodadaComErro, e.class.name
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
  # dela menos MARGEM_DO_PISO (nada antes disso ficou por ler); senão, repete o piso da anterior, para a pendente não
  # sumir da fila. A conversa já lida usa o próprio `lida_ate_em`, então a margem só relê o que é novo.
  def piso(corte)
    anterior = Autonomia::Desempenho::Rodada.do_sujeito(@account, @ficha.sujeito_type, @ficha.sujeito_id).recentes
                                            .where.not(status: 'rodando').first
    return anterior.corte_em - MARGEM_DO_PISO if anterior&.status == 'ok' && anterior.conversas_pendentes.zero?

    anterior&.piso_em || leituras.maximum(:lida_ate_em) || (corte - SEM_CARGA)
  end

  def ler_todas(credencial)
    @leitor = leitor = Autonomia::Desempenho::LeituraAutomatica::Leitor.new(account: @account, ficha: @ficha, credencial: credencial)
    @lidas = @puladas = @passageiras = @inesperados = 0
    candidatas.first(MAX_CONVERSAS).each do |conversation_id|
      return fechar('teto') if teto.passou?

      @trava.renovar
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
    resultado = tentar(leitor, conversa, mensagens, gravacao)
    @inesperados = 0
    resultado
  rescue Parada
    raise
  rescue StandardError => e
    inesperado(gravacao, conversa.id, e)
  end

  # A falha esperada (resposta recusada) é da conversa e conta para ela desistir.
  def tentar(leitor, conversa, mensagens, gravacao)
    texto = transcricao(conversa, mensagens)
    if texto.size > teto.max_caracteres
      gravacao.nao_lida!
      return :lida
    end

    resposta = chamar(leitor, texto)
    return passageira(gravacao, conversa.id) if resposta.nil?

    gravacao.gravar!(esquema.procuras(resposta))
    vezes.zerar(conversa.id)
    :lida
  rescue Autonomia::Desempenho::LeituraAutomatica::Leitor::Falha, Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida => e
    falhou(gravacao, conversa.id, e)
  end

  # Bug do sistema, não da conversa: ela fica pendente, sem contar falha; o terceiro seguido na rodada fecha a rodada.
  # A mesma conversa com erro inesperado no limite de VezesDaConversa (entre rodadas) fica como não lida.
  def inesperado(gravacao, conversation_id, erro)
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} conversa=#{conversation_id} inesperado=#{erro.class.name}")
    @inesperados += 1
    raise Parada, 'erro' if @inesperados >= INESPERADOS_PARA_PARAR
    return :pendente unless vezes.mais_uma?('inesperados', conversation_id)

    desistir_do_inesperado(gravacao, conversation_id)
  end

  # Erro passageiro na chamada desta conversa: ela fica pendente, e o terceiro seguido na rodada fecha a rodada (antes de
  # contar contra a conversa: três seguidos são a OpenAI, não ela). Só o tempo esgotado conta para a conversa; no limite
  # de VezesDaConversa (entre rodadas), ela fica como não lida.
  def passageira(gravacao, conversation_id)
    raise Parada, 'erro' if @passageiras >= PASSAGEIRAS_PARA_PARAR
    return :pendente unless @tempo_esgotado && vezes.mais_uma?('passageiras', conversation_id)

    desistir(gravacao, conversation_id)
  end

  # A conversa sai da fila como não lida, e todos os contadores dela voltam a zero: ela volta à fila com mensagem nova
  # e começa do zero.
  def desistir(gravacao, conversation_id)
    gravacao.nao_lida!
    vezes.zerar(conversation_id)
    :lida
  end

  # Se nem marcar como não lida der certo (o bug pode estar na gravação), a conversa segue pendente.
  def desistir_do_inesperado(gravacao, conversation_id)
    desistir(gravacao, conversation_id)
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{@account.id} conversa=#{conversation_id} nao_lida=#{e.class.name}")
    :pendente
  end

  # A resposta, ou nil no erro passageiro (quem chamou decide, em `passageira`). Erro permanente fecha a rodada (Parada).
  def chamar(leitor, texto)
    resposta = leitor.ler(texto, esquema.json)
    @passageiras = 0
    resposta
  rescue Crm::Ai::ResponsesClient::Error => e
    raise Parada, (CHAVE_RECUSADA.include?(e.status.to_i) ? 'chave_recusada' : 'erro') if permanente?(e)
    # Sem status e sem ser de rede (resposta vazia, já cobrada): falha da conversa.
    raise Autonomia::Desempenho::LeituraAutomatica::Leitor::Falha, e.class.name unless e.passageira?

    Rails.logger.warn("[desempenho][leitura] conta=#{@account.id} passageiro=#{e.status.to_i}")
    @passageiras += 1
    @tempo_esgotado = e.tempo_esgotado?
    nil
  end

  # 4xx que não é passageiro (401, 403, 404, 400, 422): não adianta tentar a próxima conversa. Sem status (resposta
  # vazia, já cobrada) é problema da conversa, não da conta. O 429 é passageiro aqui: a cota esgotada também volta 429,
  # e três seguidos fecham a rodada.
  def permanente?(erro) = erro.status.present? && !erro.passageira?

  def falhou(gravacao, conversation_id, erro)
    Rails.logger.warn("[desempenho][leitura] conta=#{@account.id} conversa=#{conversation_id} falha=#{erro.class.name}")
    return :pendente unless vezes.mais_uma?('falhas', conversation_id)

    desistir(gravacao, conversation_id)
  end

  def fechar(status)
    lidas = @lidas.to_i
    pendentes = [candidatas.size - lidas - @puladas.to_i, 0].max
    @rodada.update!(status: status, terminada_em: Time.current, conversas_lidas: lidas, conversas_pendentes: pendentes,
                    custo_usd: custo, pendente_desde: (fila.mais_antiga if pendentes.positive?))
    @rodada
  end

  # O gasto da rodada: o que o leitor dela somou das respostas. O consumo gravado da conta no dia não serve: ele soma
  # também as rodadas dos outros agentes da conta e as rodadas anteriores do mesmo dia.
  def custo = @leitor&.custo || 0

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

  def candidatas = @candidatas ||= fila.ids

  def fila
    @fila ||= Autonomia::Desempenho::LeituraAutomatica::Candidatas.new(
      **sujeito.except(:account_id), account: @account, remetentes: remetentes, piso: @rodada.piso_em, corte: @rodada.corte_em,
                                     piso_sem_leitura: @rodada.corte_em - SEM_CARGA
    )
  end

  def remetentes = @ficha.configuracao['remetentes_do_agente']
  def esquema = @esquema ||= Autonomia::Desempenho::LeituraAutomatica::Esquema.new(@ficha)
  def teto = @teto ||= Autonomia::Desempenho::LeituraAutomatica::Teto.new(account: @account, ficha: @ficha)
  def leituras = Autonomia::Desempenho::Leitura.do_sujeito(@account, @ficha.sujeito_type, @ficha.sujeito_id)
  def sujeito = { account_id: @account.id, sujeito_type: @ficha.sujeito_type, sujeito_id: @ficha.sujeito_id }
  def vezes = @vezes ||= Autonomia::Desempenho::LeituraAutomatica::VezesDaConversa.new(account: @account, ficha: @ficha)
end
