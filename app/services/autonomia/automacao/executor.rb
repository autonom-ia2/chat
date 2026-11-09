# Uma rodada de uma execução (#2414 F3, ADR-001 2.4): do cursor até uma espera, um "parar" ou o fim, com um registro
# por passo. A execução fica na versão em que entrou (D10).
#
# A rodada começa tomando a execução: troca a marca da reserva (`travada_em`) pela do início, numa gravação só, e
# limpa o `due_at`. Só um job ganha essa troca; um repetido (Sidekiq devolvendo o job no desligamento, reenvio
# manual) chega com a marca velha e não anda. `due_at` vazio numa execução andando quer dizer "começou": se ela
# ficar presa, a varredura a fecha como interrompida e nunca a repete. Reservada e não começada (due_at preenchido),
# a varredura a reenfileira.
#
# Antes de andar, e de novo antes de cada ação, reconfere tudo, porque o mundo muda durante a espera e durante a
# rodada: o motor ligado, a automação ligada (F3.4), o alvo ainda existe e é da conta, o Spam (F3.5) e quem ligou (D1,
# F3.7, F3.9). Problema com quem ligou pausa a automação, sem nunca trocar de pessoa. Toda gravação da execução é
# condicionada à rodada: se alguém a desligou no meio, a rodada para sem passar por cima.
#
# Cada rodada roda dentro da cadeia comum (F1) com as origens e a profundidade guardadas na execução e uma raiz nova:
# a raiz recomeça depois de cada espera. Sem isso, a marca "já rodou nesta raiz" da cadeia recusaria o passo que vem
# depois da espera como repetido.
#
# O cursor é o passo onde a execução parou (uma espera ou a ação que vai ser tentada de novo). Ao retomar:
# - o "esperar" já cumpriu o tempo e segue;
# - o "esperar até" confere a condição de novo e, vencido o prazo, segue pelo caminho "se vencer";
# - a ação roda de novo;
# - o "decidir" que decide a cada resposta (G31) decide de novo se ela chegou, ou segue esperando até o prazo; vencido,
#   a execução acaba sem mandar nada.
class Autonomia::Automacao::Executor
  TENTATIVAS = 3
  # Espera antes da 2ª e da 3ª tentativa de um erro passageiro (F3.6).
  INTERVALOS = [1.minute, 5.minutes].freeze

  Cadeia = ::Autonomia::Automacao::Cadeia
  Execucao = ::Autonomia::Automacao::Execucao
  # Passos que falam com gente (F4): só com a flag da F4.
  NATIVOS = { 'mensagem' => ::Autonomia::Automacao::PassoDeMensagem, 'avisar' => ::Autonomia::Automacao::PassoDeAviso,
              'email' => ::Autonomia::Automacao::PassoDeEmail, 'campanha' => ::Autonomia::Automacao::PassoDeCampanha }.freeze
  # Os passos de IA (F7, #2500); com eles vem a parada fora da janela (F4.4, #2573), que vale também para a mensagem.
  include ::Autonomia::Automacao::IaNoExecutor
  # O "criar card" (G4).
  include ::Autonomia::Automacao::CardNoExecutor
  # O "esperar" e o "esperar até", com a reconferência depois de gravar a espera (lote 4).
  include ::Autonomia::Automacao::EsperaNoExecutor
  # O "decidir" que volta a esperar a próxima resposta e decide de novo (G31).
  include ::Autonomia::Automacao::DecidirDeNovo

  # Chamado pelo AvancarJob com a marca de quem reservou a execução (Partida ou VarreduraJob). A execução lida antes
  # da troca guarda o `due_at` da espera, que o "esperar até" usa como prazo.
  def self.rodar(execucao_id, travada_em, raiz = nil)
    reserva = Time.zone.parse(travada_em)
    execucao = Execucao.find_by(id: execucao_id, estado: 'andando', travada_em: reserva)
    return unless execucao

    inicio = Time.current.floor(6)
    tomada = Execucao.where(id: execucao_id, estado: 'andando', travada_em: reserva)
                     .update_all(travada_em: inicio, due_at: nil, updated_at: inicio) == 1 # rubocop:disable Rails/SkipsModelValidations
    new(execucao, inicio, raiz).rodar if tomada
  end

  def initialize(execucao, marca, raiz = nil)
    @execucao = execucao
    @marca = marca
    @definicao = execucao.automacao
    @account = execucao.account
    @raiz = raiz || SecureRandom.uuid
    @roteiro = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita)
    @acesso = ::Autonomia::Automacao::Acesso.new(@definicao, chave_gatilho: @execucao.chave_gatilho)
    @tentativas = execucao.tentativas
  end

  def rodar
    @passo_atual = @execucao.cursor || 'inicio'
    return if impedida?(@passo_atual)

    Cadeia.retomar(@execucao.cadeia, @account, @raiz) { andar }
  rescue StandardError => e
    registrar_quebra(e)
    raise
  end

  private

  def andar
    passo = @execucao.cursor.blank? ? @roteiro.primeiro : @roteiro.passo(@execucao.cursor)
    @retomando = @execucao.cursor.present?
    while passo && !@parou
      passo = dar(passo)
      @retomando = false
    end
    finalizar('concluida') unless @parou
  end

  # O próximo passo, ou nil quando a rodada parou (espera, fim, erro). Um tipo por linha: a complexidade é a lista.
  def dar(passo) # rubocop:disable Metrics/CyclomaticComplexity
    @passo_atual = passo['id']
    case passo['tipo']
    when 'esperar' then esperar(passo)
    when 'esperar_ate' then esperar_ate(passo)
    when 'se' then se(passo)
    when 'acao', 'retorno' then acao(passo)
    when *NATIVOS.keys then passo_nativo(passo, NATIVOS.fetch(passo['tipo']))
    when *IA.keys then passo_de_ia(passo, IA.fetch(passo['tipo']))
    when 'ia_assumir' then passo_nativo(passo, ::Autonomia::Automacao::PassoDeIaAssumir, mensagem: false)
    when 'card' then passo_de_card(passo)
    when 'parar' then encerrar(passo['id'], 'concluida', nil, 'ok')
    # Tipo que este motor não conhece (versão salva por um código mais novo, defeito): falha com registro, nunca fecha
    # como "concluida" sem ter feito nada.
    else encerrar(passo['id'], 'falhou', 'tipo_desconhecido', 'falhou', 'tipo' => passo['tipo'].to_s)
    end
  end

  # Fecha a execução e devolve true quando ela não pode andar agora. A execução que já não é desta rodada (a varredura a
  # fechou como travada, alguém a desligou) só para, sem gravar nada por cima.
  def impedida?(passo_id)
    return @parou = true unless desta_rodada?

    estado, motivo = impedimento
    encerrar(passo_id, estado, motivo) if estado
    estado.present?
  end

  # [estado final, motivo] quando a execução não pode andar agora; nil quando pode.
  def impedimento
    return %w[parada motor_desligado] unless ::Autonomia::Automacao::Motor.ligado?(@account)
    return %w[parada desligada] unless @definicao.ativa
    # #2499: a flag dos gatilhos de card desligada é o rollback da F6; a execução aberta de gatilho de card fecha.
    return %w[parada gatilho_desligado] unless ::Autonomia::Automacao::Gatilhos.disponivel?(@execucao.chave_gatilho, @account)
    return %w[interrompida alvo_sumiu] unless alvo_da_conta?
    return %w[parada spam] if contexto.no_spam?

    motivo = motivo_de_quem_ligou
    ['parada', pausar(motivo)] if motivo
  end

  def alvo_da_conta? = alvo.present? && contexto.conta_id == @account.id

  def desta_rodada? = Execucao.exists?(id: @execucao.id, estado: 'andando', travada_em: @marca)

  # A rodada quebrou no meio (erro inesperado): fica o passo e a classe do erro, e a execução continua andando para a
  # varredura fechá-la como travada, sem repetir. A mensagem do erro vai só para o log: pode trazer dado do cliente.
  def registrar_quebra(erro)
    Rails.logger.error("[automacao][motor] quebrou execucao=#{@execucao.id} passo=#{@passo_atual} #{erro.class}: #{erro.message}")
    registrar(@passo_atual, 'falhou', 'erro_inesperado', 'erro' => erro.class.name)
  rescue StandardError => e
    Rails.logger.error("[automacao][motor] não registrou a quebra execucao=#{@execucao.id} #{e.class}: #{e.message}")
  end

  def motivo_de_quem_ligou = @acesso.motivo || ('quem_ligou_sem_acesso' unless @acesso.alcanca?(alvo))

  # Antes de cada ação: a automação, o motor, o alvo e quem ligou podem ter mudado desde o começo da rodada.
  def reconferir
    @definicao.reload
    @account.reload
    @acesso = ::Autonomia::Automacao::Acesso.new(@definicao, chave_gatilho: @execucao.chave_gatilho)
    @alvo = @contexto = nil
  end

  def se(passo)
    ramo = condicao?(passo['condicao']) ? 'entao' : 'senao'
    registrar(passo['id'], 'ok', nil, 'ramo' => ramo)
    @roteiro.entrar(passo, ramo)
  end

  def acao(passo)
    reconferir
    return if impedida?(passo['id'])

    resultado = ::Autonomia::Automacao::PassoDeAcao.executar(execucao: @execucao, passo: passo, valores: valores, acesso: @acesso)
    case resultado.tipo
    when :ok, :pulado then seguir_depois_da_acao(passo, resultado)
    when :permanente then encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados)
    when :sem_acesso then encerrar(passo['id'], 'parada', pausar(resultado.motivo), 'falhou', resultado.dados)
    else tentar_de_novo(passo, resultado)
    end
  end

  # "mensagem", "avisar" (F4), "email" (G2) e o "Passar para a agente de IA" (G15, `mensagem: false`). Reconferem tudo
  # como a ação e, se mandam mensagem, sem a flag da F4 fecham sem mandar nada (rollback). Não repetem: a mensagem que
  # deu erro no meio não é mandada de novo, porque o cliente poderia recebê-la duas vezes; a troca de dono pode já ter
  # acontecido.
  def passo_nativo(passo, classe, mensagem: true)
    reconferir
    return if impedida?(passo['id'])
    return encerrar(passo['id'], 'parada', 'mensagens_desligadas') if mensagem && !::Autonomia::Automacao::Motor.mensagens?(@account)

    resultado = classe.new(execucao: @execucao, passo: passo, alvo: alvo).executar
    # Robô do outro lado: para só nesta conversa, e a automação continua ligada (a nota já ficou). Quem ligou não vê a
    # conversa em que o passo age: pausa a automação, como na ação.
    return encerrar(passo['id'], 'parada', motivo_da_parada(resultado), 'falhou') if %i[laco sem_acesso].include?(resultado.tipo)

    janela_fechada?(resultado) ? parar_na_janela(passo, resultado) : seguir_depois_da_acao(passo, resultado)
  end

  def motivo_da_parada(resultado) = resultado.tipo == :sem_acesso ? pausar(resultado.motivo) : resultado.motivo

  # A ação mudou o alvo: o passo seguinte ("se", "esperar até") lê o valor de agora, não o de antes dela.
  def seguir_depois_da_acao(passo, resultado)
    @tentativas = 0
    @alvo = @contexto = nil
    registrar(passo['id'], resultado.tipo == :ok ? 'ok' : 'pulado', resultado.motivo, resultado.dados)
    # G55: com o registro gravado, esta execução já passou pela campanha da vez; confere se a vez fecha.
    ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(@execucao) if passo['tipo'] == 'campanha'
    @roteiro.seguinte(passo['id'])
  end

  def tentar_de_novo(passo, resultado)
    tentativa = @tentativas + 1
    dados = resultado.dados.merge('tentativa' => tentativa)
    return encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', dados) if tentativa >= TENTATIVAS

    registrar(passo['id'], 'falhou', resultado.motivo, dados)
    @tentativas = tentativa
    aguardar(passo, Time.current + INTERVALOS[tentativa - 1], registrar: false)
  end

  def aguardar(passo, ate, registrar: true)
    registrar(passo['id'], 'ok', nil, 'ate' => ate.iso8601) if registrar
    gravar(estado: 'esperando', cursor: passo['id'], due_at: ate, travada_em: nil, tentativas: @tentativas)
    nil
  end

  # Fecha a execução. Com `resultado`, deixa antes o registro do passo em que ela parou.
  def encerrar(passo_id, estado, motivo, resultado = 'pulado', dados = {})
    registrar(passo_id, resultado, motivo, dados) if resultado
    finalizar(estado)
    nil
  end

  # G55: a execução que fecha deixa de segurar a campanha da vez do recorrente de card ou contato; confere se ela fecha.
  def finalizar(estado) = gravar(estado: estado, travada_em: nil).then { ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(@execucao) }

  # Só grava na rodada que tomou a execução: se alguém a desligou no meio, nada muda e a rodada para do mesmo jeito.
  def gravar(**atributos)
    Execucao.gravar_na_rodada(@execucao.id, @marca, **atributos)
    @parou = true
  end

  # Quem ligou não pode mais agir: a automação desliga até alguém assumir e religar (F3.7). Devolve o motivo.
  def pausar(motivo)
    Rails.logger.info("[automacao][motor] pausada automacao=#{@definicao.id} conta=#{@account.id} motivo=#{motivo}")
    @definicao.update!(ativa: false)
    motivo
  end

  def registrar(passo_id, resultado, motivo = nil, dados = {})
    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @definicao, execucao: @execucao, passo: passo_id,
                                             resultado: resultado, motivo: motivo, dados: dados)
  end

  # `lidos`: o "esperar até" lê com o começo da espera, para a resposta que chegou durante ela (G11).
  def condicao?(condicao, lidos = valores) = ::Autonomia::Automacao::Condicao.new(condicao, lidos).verdadeira?

  # Lido do banco a cada reconferência: o alvo pode ter sido apagado no meio da rodada.
  def alvo = (@alvo ||= @execucao.alvo_type.constantize.find_by(id: @execucao.alvo_id))

  # As pontes do alvo (#2499): conversa, card ou contato, e os outros dois quando há caminho.
  def contexto = (@contexto ||= ::Autonomia::Automacao::Contexto.de(alvo, execucao: @execucao))

  # Com as permissões de quem ligou (#2597); no "esperar até", com a janela da espera (G11).
  def valores(espera: nil) = ::Autonomia::Automacao::Valores.new(alvo: contexto, quem: @definicao.ligada_por, espera: espera)
end
