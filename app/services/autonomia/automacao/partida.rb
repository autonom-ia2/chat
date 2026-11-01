# Uma automação começando para um alvo (#2414 F3, ADR-001 2.4 passo 2). Quem chama é a escuta dos gatilhos.
#
# Confere, nesta ordem:
# - motor ligado, automação ligada e com versão;
# - alvo da conta e fora do Spam (F3.5);
# - quem ligou (sem ela ou sem permissão, a automação pausa, e o porquê fica no histórico);
# - a caixa (D5): quem não é administrador só automatiza o que alcança, e o resto é pulado;
# - os filtros do gatilho;
# - a cadeia comum (D6: laço, profundidade, repetida).
#
# Passou: grava a execução reservada (estado "andando", com a marca `travada_em` e o `due_at` preenchido, que quer
# dizer "ainda não começou": ver Executor) e enfileira a primeira rodada, na mesma raiz do evento que a disparou. Já
# existe uma aberta para a mesma automação, alvo e gatilho? Não abre outra (índice único, F2.5).
class Autonomia::Automacao::Partida
  Cadeia = ::Autonomia::Automacao::Cadeia

  # `mensagem`: a que disparou o gatilho mensagem.criada, para o filtro (mensagem.tipo).
  def initialize(definicao:, alvo:, chave_gatilho:, mensagem: nil)
    @definicao = definicao
    @account = definicao.account
    @alvo = alvo
    @chave_gatilho = chave_gatilho
    @mensagem = mensagem
  end

  # A execução aberta, ou nil quando não começou.
  def call
    return unless pode_comecar?

    acesso = ::Autonomia::Automacao::Acesso.new(@definicao)
    return pausar(acesso.motivo) if acesso.motivo
    return pular('fora_do_alcance') unless acesso.alcanca?(@alvo)
    return pular('fora_do_filtro') unless no_filtro?
    return pular('ja_aberta') if aberta?

    comecar
  end

  private

  def pode_comecar?
    ::Autonomia::Automacao::Motor.ligado?(@account) && @definicao.ativa && @definicao.versao_ativa &&
      @alvo.account_id == @account.id && !::ConversaCanal::PastaDoEmail.no_spam?(@alvo)
  end

  # A mensagem nova numa conversa que já tem a execução aberta é o caso comum: a consulta evita a cadeia e o INSERT
  # que o índice único recusaria. O índice continua sendo a garantia (corrida entre dois eventos).
  def aberta?
    ::Autonomia::Automacao::Execucao.abertas.exists?(automacao_id: @definicao.id, alvo: @alvo, chave_gatilho: @chave_gatilho)
  end

  def no_filtro?
    valores = ::Autonomia::Automacao::Valores.new(conversa: @alvo, mensagem: @mensagem)
    Array(@definicao.versao_ativa.receita.dig('gatilho', 'filtros')).all? do |condicao|
      ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
    end
  end

  def comecar
    resultado = Cadeia.entrar(::Autonomia::Automacao::Motor.origem(@definicao), @account) { abrir }
    return resultado unless resultado.is_a?(Cadeia::Recusa)

    Cadeia.registrar_recusa(resultado, account_id: @account.id, alvo: "conversa:#{@alvo.id}", conversa: @alvo, nome: @definicao.nome)
    nil
  end

  def abrir
    marca = Time.current.floor(6)
    execucao = criar(estado: 'andando', travada_em: marca, due_at: marca, cadeia: Cadeia.origens, profundidade: Cadeia.origens.size)
    ::Autonomia::Automacao::AvancarJob.perform_later(execucao.id, marca.iso8601(6), Cadeia.raiz)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Quem ligou perdeu a vez: a automação desliga, e a execução fechada guarda o porquê para a tela (F3.7).
  def pausar(motivo)
    Rails.logger.info("[automacao][motor] pausada automacao=#{@definicao.id} conta=#{@account.id} motivo=#{motivo}")
    @definicao.update!(ativa: false)
    execucao = criar(estado: 'parada')
    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @definicao, execucao: execucao, passo: 'inicio',
                                             resultado: 'pulado', motivo: motivo)
    nil
  end

  def pular(motivo)
    Rails.logger.debug { "[automacao][motor] pulada automacao=#{@definicao.id} alvo=conversa:#{@alvo.id} motivo=#{motivo}" }
    nil
  end

  def criar(**atributos)
    ::Autonomia::Automacao::Execucao.create!(account: @account, automacao: @definicao, versao: @definicao.versao_ativa, alvo: @alvo,
                                             chave_gatilho: @chave_gatilho, **atributos)
  end
end
