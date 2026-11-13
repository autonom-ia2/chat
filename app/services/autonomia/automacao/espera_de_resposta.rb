# A espera dos passos que perguntam e esperam alguém responder (PassosQueEsperam: aprovação, reunião e pesquisa), no
# Executor. Um mecanismo só para os três, em cima da espera que o motor já tem (o `due_at`, a varredura e a reserva da
# Escuta), sem tabela nova:
#
# 1. Ao chegar no passo, ele pergunta (a classe do passo: manda a mensagem ao cliente, ou acha quem aprova). O registro
#    do passo (motivo `esperando_resposta`) guarda o que a resposta vai precisar: o marco das mensagens do cliente
#    (Resposta.marco, a régua do G31), os horários oferecidos, quem aprova. A execução espera até o prazo do passo.
# 2. Acordada (a mensagem nova do cliente pela Escuta, a resposta do painel, ou a varredura no prazo), a classe lê a
#    resposta. Com resposta, segue pelo galho dela. Sem resposta ainda (ou ambígua, que a IA não soube dizer), volta a
#    esperar com o mesmo prazo. Vencido o prazo sem resposta, segue pelo galho "sem resposta" do passo.
#
# Antes de perguntar e de novo a cada vez que acorda, reconfere tudo, como a ação: o motor, a automação, quem ligou e o
# alcance dele (Executor#impedida?), e a flag dos passos novos: desligada, a execução para naquele ponto, sem mandar nada
# (o rollback da flag). A janela de 24 h fechada sem modelo que saia no lugar para a execução nesta conversa, como a
# mensagem (JanelaFechada, decisão do Rodrigo de 12/11).
#
# A corrida do acordar: a resposta que chega entre a pergunta e a espera gravada acha a execução ainda andando, e ninguém
# a acorda. Por isso, gravada a espera, confere uma vez se o cliente já respondeu e, se sim, reserva pela mesma reserva da
# Escuta (Despertador.acordar). A aprovação só aparece para quem aprova depois da espera gravada (`depois_de_esperar`).
module Autonomia::Automacao::EsperaDeResposta
  Esperam = ::Autonomia::Automacao::PassosQueEsperam
  ESPERANDO = 'esperando_resposta'.freeze
  # O marco novo depois de uma resposta que a IA não soube dizer: a próxima conta a partir dele.
  AMBIGUA = 'resposta_ambigua'.freeze

  private

  def passo_que_espera(passo)
    retomando = @retomando
    reconferir
    return if impedida?(passo['id'])

    desligado = Esperam.desligado(passo, @account)
    return encerrar(passo['id'], 'parada', desligado) if desligado

    retomando ? conferir_resposta(passo) : perguntar(passo)
  end

  def classe_que_espera(passo) = Esperam.classe(passo).new(execucao: @execucao, passo: passo, alvo: alvo, acesso: @acesso)

  def perguntar(passo)
    resultado = classe_que_espera(passo).perguntar
    return esperar_quem_responde(passo, resultado.dados) if resultado.tipo == :esperar

    depois_da_pergunta(passo, resultado)
  end

  # O que não espera: o galho na hora (ninguém para aprovar, pesquisa recente), o pulo, a janela fechada, o robô.
  def depois_da_pergunta(passo, resultado)
    return parar_na_janela(passo, resultado) if janela_fechada?(resultado)
    return seguir_depois_da_acao(passo, resultado) if %i[ok pulado].include?(resultado.tipo)
    return encerrar(passo['id'], 'parada', motivo_da_parada(resultado), 'falhou') if %i[laco sem_acesso].include?(resultado.tipo)

    encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados)
  end

  # O nome não é `esperar_resposta`: esse é o do "decidir de novo" (DecidirDeNovo), no mesmo Executor.
  def esperar_quem_responde(passo, dados, ate = Time.current + ::Autonomia::Automacao::Duracao.de(Esperam.prazo(passo)))
    registro = registrar(passo['id'], 'ok', ESPERANDO, dados.merge('ate' => ate.iso8601))
    aguardar(passo, ate, registrar: false)
    depois_de_esperar(passo, registro)
    nil
  end

  # Só depois da espera gravada: o aviso a quem aprova e a corrida da resposta. O erro aqui vai para o log e para o
  # histórico da execução, e a espera segue pelo relógio.
  def depois_de_esperar(passo, registro)
    esperando = ::Autonomia::Automacao::Execucao.find_by(id: @execucao.id, estado: 'esperando')
    return unless esperando

    classe_que_espera(passo).depois_de_esperar(registro)
    ::Autonomia::Automacao::Despertador.acordar(esperando) if Esperam.espera_o_cliente?(passo) && cliente_ja_respondeu?(registro)
  rescue StandardError => e
    ::Autonomia::Automacao::Despertador.nao_acordou(@execucao, e, passo: passo['id'])
  end

  def cliente_ja_respondeu?(registro)
    marco = registro.dados['marco']
    marco.present? && ::Autonomia::Automacao::Resposta.cliente_depois?(contexto.contato, marco, nil, @definicao.ligada_por)
  end

  # Acordada: a resposta (até o prazo, que é o `due_at` lido antes da troca), ou volta a esperar, ou o galho sem resposta.
  def conferir_resposta(passo)
    pedido = pedido_da_espera(passo)
    return encerrar(passo['id'], 'falhou', 'pedido_sumiu', 'falhou') unless pedido

    resultado = classe_que_espera(passo).resposta(pedido, marco: marco_da_espera(passo, pedido), ate: @execucao.due_at)
    seguir_pela_resposta(passo, pedido, resultado)
  end

  def seguir_pela_resposta(passo, pedido, resultado)
    case resultado.tipo
    when :ok, :pulado then seguir_depois_da_acao(passo, resultado)
    when :de_novo then esperar_quem_responde(passo, resultado.dados)
    when :laco, :sem_acesso then encerrar(passo['id'], 'parada', motivo_da_parada(resultado), 'falhou')
    else sem_resposta_ainda(passo, pedido, resultado)
    end
  end

  # :esperar (nada ainda, ou ambígua com marco novo) e :passageiro (a IA não respondeu): espera de novo até o prazo; no
  # prazo, o galho sem resposta. A aprovação fecha o pedido antes: a resposta que chegar depois é recusada no painel.
  def sem_resposta_ainda(passo, pedido, resultado)
    registrar(passo['id'], 'ok', AMBIGUA, resultado.dados.slice('marco')) if resultado.dados['marco']
    return aguardar(passo, @execucao.due_at, registrar: false) if @execucao.due_at&.future?

    decidida = classe_que_espera(passo).fechar(pedido)
    return seguir_depois_da_acao(passo, decidida) if decidida

    motivo = resultado.tipo == :passageiro ? resultado.motivo : 'prazo_vencido'
    registrar(passo['id'], 'pulado', motivo, 'ramo' => Esperam.sem_resposta(passo))
    @roteiro.entrar(passo, Esperam.sem_resposta(passo))
  end

  # O pedido da espera atual: o último registro `esperando_resposta` deste passo.
  def pedido_da_espera(passo) = registros_do_passo(passo).where(motivo: ESPERANDO).order(:id).last

  # O marco mais novo desde o pedido: o da pergunta, ou o da última resposta ambígua.
  def marco_da_espera(passo, pedido)
    ambigua = registros_do_passo(passo).where(motivo: AMBIGUA).where('id > ?', pedido.id).order(:id).last
    (ambigua || pedido).dados['marco']
  end

  def registros_do_passo(passo) = ::Autonomia::Automacao::Registro.where(execucao_id: @execucao.id, passo: passo['id'])
end
