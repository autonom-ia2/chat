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
# existe uma aberta para a mesma automação, alvo e gatilho? Não abre outra (índice único, F2.5), salvo quando a
# receita escolheu `se_repetir: comeca_outra` (G50): aí abre outra, paralela, pela mesma cadeia, Acesso e filtros.
class Autonomia::Automacao::Partida
  Cadeia = ::Autonomia::Automacao::Cadeia

  # `mensagem`: a que disparou o gatilho mensagem.criada, para o filtro (mensagem.tipo).
  # `evento`: a marca única do fato que disparou (ver Gatilhos); sem ela, a da mensagem.
  def initialize(definicao:, alvo:, chave_gatilho:, mensagem: nil, evento: nil)
    @definicao = definicao
    @account = definicao.account
    @alvo = alvo
    @chave_gatilho = chave_gatilho
    @mensagem = mensagem
    @evento = evento || (mensagem && "mensagem:#{mensagem.id}")
  end

  # A execução aberta, ou nil quando não começou.
  def call
    return unless pode_comecar?
    return if ja_aconteceu?

    acesso = ::Autonomia::Automacao::Acesso.new(@definicao, chave_gatilho: @chave_gatilho)
    return pausar(acesso.motivo) if acesso.motivo
    return pular('fora_do_alcance') unless acesso.alcanca?(@alvo)
    return pular('fora_do_filtro') unless no_filtro?
    return ja_aberta if ja_aberta?

    comecar
  end

  private

  def pode_comecar?
    @definicao.ativa && @definicao.versao_ativa && ::Autonomia::Automacao::Gatilhos.disponivel?(@chave_gatilho, @account) &&
      contexto.conta_id == @account.id && !contexto.no_spam?
  end

  def gatilho = @definicao.versao_ativa.receita['gatilho'].to_h

  # G50: a receita pediu outra execução quando o gatilho se repete (a 2ª falta do aluno com a 1ª ainda esperando). O
  # esquema e o salvar só deixam isso nos gatilhos de evento que aceitam (Gatilhos.pode_repetir?).
  def paralela? = ::Autonomia::Automacao::Gatilhos.comeca_outra?(gatilho)

  # O mesmo fato já abriu uma execução (o evento repetido, ou a varredura de tempo achando o mesmo card de novo a cada
  # rodada): não passa pela cadeia nem tenta o INSERT. Pelo índice único (automacao_id, evento); o índice segue sendo a
  # garantia na corrida.
  def ja_aconteceu?
    @evento.present? && ::Autonomia::Automacao::Execucao.exists?(automacao_id: @definicao.id, evento: @evento)
  end

  # A mensagem nova numa conversa que já tem a execução aberta é o caso comum: a consulta evita a cadeia e o INSERT
  # que o índice único recusaria. O índice continua sendo a garantia (corrida entre dois eventos).
  def aberta?
    execucao_aberta.present?
  end

  # A paralela (G50) não pergunta pela aberta: começa ao lado dela.
  def ja_aberta? = !paralela? && aberta?

  def execucao_aberta
    @execucao_aberta ||= ::Autonomia::Automacao::Execucao.abertas.find_by(automacao_id: @definicao.id, alvo: @alvo,
                                                                          chave_gatilho: @chave_gatilho)
  end

  # O gatilho aconteceu de novo com a execução ainda rodando (esperando, por exemplo): não abre outra, e o histórico da
  # que está aberta diz isso ao dono. Uma linha por execução: a mensagem nova numa conversa com a execução aberta é o
  # caso comum, e não pode encher o histórico. A hora da repetição fica na execução, e o "esperar até" que espera por
  # ela (`gatilho.repetiu`, lote 4) acorda agora.
  def ja_aberta
    execucao = execucao_aberta
    execucao.update_columns(repetiu_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
    ::Autonomia::Automacao::Despertador.acordar(execucao)
    return if ::Autonomia::Automacao::Registro.exists?(execucao: execucao, resultado: 'pulado', motivo: 'ja_aberta')

    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @definicao, execucao: execucao, passo: 'inicio',
                                             resultado: 'pulado', motivo: 'ja_aberta')
    nil
  end

  def no_filtro?
    valores = ::Autonomia::Automacao::Valores.new(alvo: @alvo, mensagem: @mensagem, quem: @definicao.ligada_por)
    Array(gatilho['filtros']).all? do |condicao|
      ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
    end
  end

  def comecar
    resultado = Cadeia.entrar(::Autonomia::Automacao::Motor.origem(@definicao), @account) { abrir }
    return resultado unless resultado.is_a?(Cadeia::Recusa)

    Cadeia.registrar_recusa(resultado, account_id: @account.id, alvo: rotulo_do_alvo, conversa: contexto.conversa, nome: @definicao.nome)
    nil
  end

  # O índice único da execução aberta barra a segunda partida enquanto a primeira anda; o do evento barra o mesmo evento
  # entregue de novo depois que ela fechou (o EventDispatcherJob repete). Os dois caem no RecordNotUnique, antes de
  # qualquer passo. A paralela (G50) não conta no da execução aberta; o do evento continua valendo para ela.
  def abrir
    marca = Time.current.floor(6)
    execucao = criar(estado: 'andando', travada_em: marca, due_at: marca, cadeia: Cadeia.origens, profundidade: Cadeia.origens.size,
                     evento: @evento, paralela: paralela?)
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
    Rails.logger.debug { "[automacao][motor] pulada automacao=#{@definicao.id} alvo=#{rotulo_do_alvo} motivo=#{motivo}" }
    nil
  end

  def contexto = @contexto ||= ::Autonomia::Automacao::Contexto.de(@alvo)

  # Para o log: o tipo e o id do banco, sem nome nem título (podem ser do cliente).
  def rotulo_do_alvo = "#{contexto.base}:#{@alvo.id}"

  def criar(**atributos)
    ::Autonomia::Automacao::Execucao.create!(account: @account, automacao: @definicao, versao: @definicao.versao_ativa, alvo: @alvo,
                                             chave_gatilho: @chave_gatilho, **atributos)
  end
end
