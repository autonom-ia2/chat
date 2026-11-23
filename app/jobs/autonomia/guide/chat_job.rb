# Responde uma pergunta ao Guia fora da requisição (issue #572).
#
# Existe porque o `rack-timeout` de produção mata qualquer requisição aos 15
# segundos, e cada ida ao gpt-5.6-sol leva de 3 a 5. Dentro da requisição cabia
# uma leitura; uma pergunta que pedisse a segunda morria com erro 500. Aqui não
# há requisição para morrer, e o Guia lê quantas vezes precisar.
#
# Roda na fila `medium`, como a geração de e-mail, que faz o mesmo tipo de
# trabalho. Ocupa uma thread do Sidekiq enquanto pensa — e NENHUMA do painel.
#
# #861 — depois de responder, grava no turno da conversa a resposta e o
# diagnóstico do pedido (`Registro`). Aqui, e não durante o Guia: dentro de
# `Diario.gravando` toda escrita vira mudança do Guia, e o desfazer levaria junto
# o próprio registro.
class Autonomia::Guide::ChatJob < ApplicationJob
  queue_as :medium

  attr_reader :registro

  # A pergunta é de uma pessoa, num momento. Repetir sozinho, minutos depois,
  # entregaria uma resposta que ela já desistiu de esperar — e a tela só busca
  # durante a validade do pedido. Falhou, falhou: a tela diz, e ela pergunta de
  # novo se quiser.
  discard_on StandardError do |job, error|
    Rails.logger.error(
      "[autonomia][guide][chat_job] pedido=#{job.arguments.first} #{error.class}: #{error.message}\n" \
      "#{Array(error.backtrace).first(5).join("\n")}"
    )
    job.send(:falhou, error)
  end

  # `pergunta` traz quem perguntou, o quê, o histórico da conversa, a tela em
  # que a pessoa estava e o idioma dela. O idioma vem da requisição: a frase do
  # botão de confirmar e o aviso de que apagar não tem volta saem do I18n, e o
  # job não herda o idioma de ninguém.
  def perform(pedido_id, pergunta)
    account = Account.find_by(id: pergunta['account_id'])
    user = User.find_by(id: pergunta['user_id'])
    return sem_dono(pedido_id) if account.nil? || user.nil?

    @registro = ::Autonomia::Guide::Registro.new
    resultado = @registro.ativo do
      I18n.with_locale(pergunta['locale']) { responder(account, user, pedido_id, pergunta) }
    end
    ::Autonomia::Guide::Turno.concluir(pedido_id, resultado.to_h, diagnostico_de(resultado))
    # Daqui em diante a resposta existe: um erro no fim do turno não pode reescrevê-la como falha.
    @turno_concluido = true
    encerrar(pedido_id, pergunta, respondeu: respondeu?(resultado)) do |seguinte|
      ::Autonomia::Guide::Pedido.concluir(pedido_id, resultado.to_h.merge(seguinte))
    end
  end

  private

  def falhou(error)
    pedido_id, pergunta = arguments
    # Só a classe do erro: a mensagem pode trazer o prompt ou dado da conta.
    unless @turno_concluido
      ::Autonomia::Guide::Turno.falhar(pedido_id, (registro || ::Autonomia::Guide::Registro.new).diagnostico(erro: error.class.name))
    end
    encerrar(pedido_id, pergunta, respondeu: false) { |seguinte| ::Autonomia::Guide::Pedido.falhar(pedido_id, seguinte) }
  rescue StandardError => e
    # Sem a trava, ao menos a tela para de esperar.
    Rails.logger.error("[autonomia][guide][chat_job] encerrar pedido=#{pedido_id} #{e.class}")
    ::Autonomia::Guide::Pedido.falhar(pedido_id)
  end

  # O Guia respondeu de fato: as mensagens que ele leu no meio do trabalho foram respondidas junto.
  def respondeu?(resultado)
    resultado.available == true && resultado.text.present?
  end

  # O "pronto" do pedido sai com a fila de mensagens travada (`Pedido.com_trava`): o que a pessoa escreveu durante o
  # turno não se perde. O que o Guia não respondeu vira a pergunta seguinte, que roda logo depois desta e já lê esta
  # resposta no histórico; a tela sabe dela por `seguinte`. Trava ocupada: a resposta sai mesmo assim.
  def encerrar(pedido_id, pergunta, respondeu:)
    ::Autonomia::Guide::Pedido.com_trava(pedido_id) { yield encaminhar(pedido_id, pergunta, respondeu) }
  rescue ::Autonomia::Guide::Pedido::TravaOcupada
    Rails.logger.error("[autonomia][guide][chat_job] trava ocupada no fim do turno pedido=#{pedido_id}")
    yield({})
  end

  # Lidas e respondidas ficam juntas deste pedido (o turno delas já é `junto` dele). Lidas sem resposta (falha,
  # resposta retida) e as que chegaram depois da última rodada seguem adiante.
  # -> { 'seguinte' => pedido que vai responder, 'tardias' => pedidos das mensagens que ele cobre } ou {}.
  def encaminhar(pedido_id, pergunta, respondeu)
    lidas = ::Autonomia::Guide::Pedido.retirar_lidas(pedido_id)
    lidas.each { |junta| ::Autonomia::Guide::Pedido.concluir(junta['id'], { 'junto_de' => pedido_id }) } if respondeu
    adiante = (respondeu ? [] : lidas) + ::Autonomia::Guide::Pedido.retirar_juntas(pedido_id)
    adiante.empty? ? {} : seguir(adiante, pergunta)
  end

  def seguir(adiante, pergunta)
    seguinte = adiante.last['id']
    adiante[0...-1].each do |junta|
      ::Autonomia::Guide::Pedido.concluir(junta['id'], { 'junto_de' => seguinte })
      ::Autonomia::Guide::Turno.juntar(junta['id'], seguinte)
    end
    ::Autonomia::Guide::Turno.reabrir(seguinte)
    self.class.perform_later(seguinte, pergunta_seguinte(seguinte, adiante, pergunta))
    { 'seguinte' => seguinte, 'tardias' => adiante.pluck('id') }
  rescue StandardError => e
    # A resposta deste pedido sai mesmo assim. As mensagens que iam adiante ficam sem resposta: o log diz quantas.
    Rails.logger.error("[autonomia][guide][chat_job] pergunta seguinte pedido=#{seguinte} mensagens=#{adiante.size} #{e.class}")
    {}
  end

  # A mesma pessoa, tela e idioma; o texto é o que ela escreveu, e o histórico já traz a resposta que acabou de sair.
  # Os anexos eram da pergunta anterior: o Guia não os relê.
  def pergunta_seguinte(seguinte, adiante, pergunta)
    conversa = ::Autonomia::Guide::Turno.find_by(pedido_id: seguinte)&.conversa
    pergunta.merge('mensagem' => adiante.pluck('texto').join("\n\n"), 'arquivos' => [],
                   'historico' => conversa ? conversa.historico(exceto: seguinte) : pergunta['historico'])
  end

  def responder(account, user, pedido_id, pergunta)
    ::Autonomia::Guide::Chat.new(account: account, user: user, message: pergunta['mensagem'],
                                 history: pergunta['historico'], route_context: pergunta['tela'],
                                 route_params: pergunta['parametros'], tela: pergunta['contexto_tela'],
                                 arquivos: pergunta['arquivos'], registro: @registro, pedido_id: pedido_id,
                                 turno_id: ::Autonomia::Guide::Turno.where(pedido_id: pedido_id).pick(:id)).perform
  end

  def sem_dono(pedido_id)
    ::Autonomia::Guide::Pedido.falhar(pedido_id)
    ::Autonomia::Guide::Turno.falhar(pedido_id, ::Autonomia::Guide::Registro.new.diagnostico(erro: 'sem_conta_ou_pessoa'))
  end

  # O Guia fora do ar (`Chat#unavailable`) não levanta: devolve "indisponível".
  # O registro diz isso, para não parecer resposta.
  def diagnostico_de(resultado)
    @registro.diagnostico(erro: (resultado.available ? nil : 'indisponivel'))
  end
end
