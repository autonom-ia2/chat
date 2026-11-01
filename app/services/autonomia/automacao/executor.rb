# Uma rodada de uma execução (#2414 F3, ADR-001 2.4): do cursor até uma espera, um "parar" ou o fim, com um registro
# por passo. A execução fica na versão em que entrou (D10).
#
# Antes de andar, reconfere tudo, porque o mundo mudou durante a espera: o motor ligado, a automação ligada (F3.4), o
# alvo ainda existe e é da conta, o Spam (F3.5) e quem ligou (D1, F3.7, F3.9). Problema com quem ligou pausa a
# automação, sem nunca trocar de pessoa.
#
# Cada rodada roda dentro da cadeia comum (F1) com as origens e a profundidade guardadas na execução e uma raiz nova:
# a raiz recomeça depois de cada espera. Sem isso, a marca "já rodou nesta raiz" da cadeia recusaria o passo que vem
# depois da espera como repetido.
#
# O cursor é o passo onde a execução parou (uma espera ou a ação que vai ser tentada de novo). Ao retomar:
# - o "esperar" já cumpriu o tempo e segue;
# - o "esperar até" confere a condição de novo e, vencido o prazo, segue pelo caminho "se vencer";
# - a ação roda de novo.
class Autonomia::Automacao::Executor
  TENTATIVAS = 3
  # Espera antes da 2ª e da 3ª tentativa de um erro passageiro (F3.6).
  INTERVALOS = [1.minute, 5.minutes].freeze
  UNIDADES = { 'minutos' => :minutes, 'horas' => :hours, 'dias' => :days }.freeze

  Cadeia = ::Autonomia::Automacao::Cadeia

  # Chamado pelo AvancarJob. `travada_em` é a marca de quem reservou a execução (Partida ou VarreduraJob): só a rodada
  # com a marca certa anda, e um job repetido não anda duas vezes.
  def self.rodar(execucao_id, travada_em, raiz = nil)
    execucao = ::Autonomia::Automacao::Execucao.find_by(id: execucao_id, estado: 'andando', travada_em: Time.zone.parse(travada_em))
    new(execucao, raiz).rodar if execucao
  end

  def initialize(execucao, raiz = nil)
    @execucao = execucao
    @definicao = execucao.automacao
    @account = execucao.account
    @raiz = raiz || SecureRandom.uuid
    @roteiro = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita)
    @acesso = ::Autonomia::Automacao::Acesso.new(@definicao)
  end

  def rodar
    estado, motivo = impedimento
    return encerrar(@execucao.cursor || 'inicio', estado, motivo) if estado

    Cadeia.retomar(@execucao.cadeia, @account, @raiz) { andar }
  end

  private

  # [estado final, motivo] quando a execução não pode andar agora; nil quando pode.
  def impedimento
    return %w[parada motor_desligado] unless ::Autonomia::Automacao::Motor.ligado?(@account)
    return %w[parada desligada] unless @definicao.ativa
    return %w[interrompida alvo_sumiu] unless alvo_da_conta?
    return %w[parada spam] if ::ConversaCanal::PastaDoEmail.no_spam?(alvo)

    motivo = motivo_de_quem_ligou
    ['parada', pausar(motivo)] if motivo
  end

  def alvo_da_conta? = alvo.present? && alvo.account_id == @account.id

  def motivo_de_quem_ligou = @acesso.motivo || ('quem_ligou_sem_acesso' unless @acesso.alcanca?(alvo))

  def andar
    passo = @execucao.cursor.blank? ? @roteiro.primeiro : @roteiro.passo(@execucao.cursor)
    @retomando = @execucao.cursor.present?
    while passo
      passo = dar(passo)
      @retomando = false
    end
    finalizar('concluida') unless @parou
  end

  # O próximo passo, ou nil quando a rodada parou (espera, fim, erro).
  def dar(passo)
    case passo['tipo']
    when 'esperar' then esperar(passo)
    when 'esperar_ate' then esperar_ate(passo)
    when 'se' then se(passo)
    when 'acao' then acao(passo)
    when 'parar' then encerrar(passo['id'], 'concluida', nil, 'ok')
    end
  end

  def esperar(passo)
    return @roteiro.seguinte(passo['id']) if @retomando

    aguardar(passo, Time.current + duracao(passo['duracao']))
  end

  def esperar_ate(passo)
    if condicao?(passo['condicao'])
      registrar(passo['id'], 'ok')
      return @roteiro.seguinte(passo['id'])
    end
    return aguardar(passo, Time.current + duracao(passo['prazo'])) unless @retomando
    return aguardar(passo, @execucao.due_at) if @execucao.due_at.future?

    registrar(passo['id'], 'pulado', 'prazo_vencido')
    @roteiro.entrar(passo, 'se_vencer')
  end

  def se(passo)
    ramo = condicao?(passo['condicao']) ? 'entao' : 'senao'
    registrar(passo['id'], 'ok', nil, 'ramo' => ramo)
    @roteiro.entrar(passo, ramo)
  end

  def acao(passo)
    resultado = ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo, valores: valores, acesso: @acesso).executar
    case resultado.tipo
    when :ok, :pulado then seguir_depois_da_acao(passo, resultado)
    when :permanente then encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados)
    when :sem_acesso then encerrar(passo['id'], 'parada', pausar(resultado.motivo), 'falhou', resultado.dados)
    else tentar_de_novo(passo, resultado)
    end
  end

  def seguir_depois_da_acao(passo, resultado)
    @execucao.tentativas = 0
    registrar(passo['id'], resultado.tipo == :ok ? 'ok' : 'pulado', resultado.motivo, resultado.dados)
    @roteiro.seguinte(passo['id'])
  end

  def tentar_de_novo(passo, resultado)
    tentativa = @execucao.tentativas + 1
    dados = resultado.dados.merge('tentativa' => tentativa)
    return encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', dados) if tentativa >= TENTATIVAS

    registrar(passo['id'], 'falhou', resultado.motivo, dados)
    @execucao.tentativas = tentativa
    aguardar(passo, Time.current + INTERVALOS[tentativa - 1], registrar: false)
  end

  def aguardar(passo, ate, registrar: true)
    registrar(passo['id'], 'ok', nil, 'ate' => ate.iso8601) if registrar
    @execucao.update!(estado: 'esperando', cursor: passo['id'], due_at: ate, travada_em: nil)
    @parou = true
    nil
  end

  # Fecha a execução. Com `resultado`, deixa antes o registro do passo em que ela parou.
  def encerrar(passo_id, estado, motivo, resultado = 'pulado', dados = {})
    registrar(passo_id, resultado, motivo, dados) if resultado
    finalizar(estado)
    nil
  end

  # Sem validar: a execução cujo alvo sumiu (ou mudou de conta) não passa no `belongs_to`, e fechar só muda o estado.
  def finalizar(estado)
    @execucao.assign_attributes(estado: estado, travada_em: nil)
    @execucao.save!(validate: false)
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

  def condicao?(condicao)
    ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
  end

  def duracao(duracao)
    duracao['valor'].public_send(UNIDADES.fetch(duracao['unidade']))
  end

  def alvo
    @alvo ||= @execucao.alvo
  end

  def valores
    @valores ||= ::Autonomia::Automacao::Valores.new(conversa: alvo)
  end
end
