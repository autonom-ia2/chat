# O que a Automação livre ouve dos eventos da plataforma (#2414 F3, #2459). Quem chama é o AutomacaoListener.
#
# - `comecar`: o gatilho aconteceu (conversa criada, aberta, resolvida, mensagem criada). Cada automação ligada da
#   conta com esse gatilho tenta começar para a conversa (Partida, que confere quem ligou, a caixa, os filtros e a
#   cadeia).
# - `mensagem_criada`: o gatilho "mensagem.criada" e o despertar da conversa dela. A flag vem antes de carregar a
#   conversa: é o evento mais frequente da plataforma.
# - `acordar`: a conversa (ou o contato dela) mudou. Quem espera num "esperar até" por ela, também o card cuja
#   conversa principal é ela, é reservado e confere a condição agora, em vez de esperar o prazo. Só o "esperar até":
#   a ação que espera uma nova tentativa e o "esperar" de tempo seguem o relógio.
#
# O gate é a flag do motor, lida da conta: conta sem o motor só lê a conta. Com o motor, uma consulta pela conta e pelo
# tipo do gatilho; não há cache, porque a lista muda a cada automação ligada ou desligada, e uma lista velha ligaria o
# que já foi desligado.
#
# Falha aqui vai para o log e não para as outras automações, nem o evento: o EventDispatcherJob tenta de novo, e
# repetiria os webhooks e avisos dos outros listeners. Vale para o método inteiro (o Motor.ligado? e as consultas
# também) e, dentro dele, para cada automação e cada execução. O log leva a classe do erro e onde ele saiu, nunca a
# mensagem: a de uma consulta traz os valores, que podem ser do cliente. A automação que não começou por erro não
# deixa registro (não há execução onde pôr); o "esperar até" que não acordou segue pelo relógio.
#
# A execução acordada não herda a cadeia de quem a acordou: retoma a dela, gravada na Partida. A proteção contra
# laço vale nas partidas; cada receita tem um número finito de esperas, então o despertar não gira sem fim.
module Autonomia::Automacao::Escuta
  module_function

  # `alvo`: a conversa, o card ou o contato do gatilho (Gatilhos). `evento`: a marca única do fato.
  def comecar(alvo, tipo, mensagem: nil, evento: nil)
    return unless alvo && ::Autonomia::Automacao::Motor.ligado?(alvo.account)

    automacoes_do_gatilho(alvo.account_id, tipo).includes(:account, :versao_ativa, :ligada_por).find_each do |definicao|
      ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, mensagem: mensagem, evento: evento).call
    rescue StandardError => e
      registrar_erro("não começou automacao=#{definicao.id} alvo=#{alvo.class.name}:#{alvo.id}", e)
    end
  rescue StandardError => e
    registrar_erro("não ouviu gatilho=#{tipo} alvo=#{alvo&.class&.name}:#{alvo&.id}", e)
  end

  # Atividade (o histórico que a própria plataforma escreve) não é mensagem de ninguém. Nota privada conta: é mensagem
  # da equipe na conversa.
  def mensagem_criada(mensagem)
    return if mensagem.activity? || !::Autonomia::Automacao::Motor.ligado?(mensagem.account)

    comecar(mensagem.conversation, 'mensagem.criada', mensagem: mensagem)
    acordar(mensagem, [mensagem.conversation_id])
  rescue StandardError => e
    registrar_erro("não ouviu mensagem=#{mensagem&.id}", e)
  end

  # `registro`: o que mudou (conversa, contato ou mensagem); a conta sai dele aqui dentro, sob o rescue.
  # `conversa_ids`: lista ou subconsulta de ids das conversas.
  def acordar(registro, conversa_ids)
    account = registro.account
    return unless ::Autonomia::Automacao::Motor.ligado?(account)

    esperando_pela_conversa(account, conversa_ids).includes(:versao).find_each do |execucao|
      reservar(execucao) if esperando_condicao?(execucao)
    rescue StandardError => e
      registrar_erro("não acordou execucao=#{execucao.id}", e)
    end
  rescue StandardError => e
    registrar_erro("não acordou #{registro.class.name}=#{registro&.id}", e)
  end

  # Quem espera pela conversa: a execução dela e a do card cuja conversa principal é ela (G11: a resposta do cliente
  # acorda o card na hora, em vez de no fim do prazo).
  def esperando_pela_conversa(account, conversa_ids)
    execucoes = ::Autonomia::Automacao::Execucao.where(account_id: account.id, estado: 'esperando')
    cards = ::Crm::Card.where(account_id: account.id, conversation_id: conversa_ids).select(:id)
    execucoes.where(alvo_type: 'Conversation', alvo_id: conversa_ids).or(execucoes.where(alvo_type: 'Crm::Card', alvo_id: cards))
  end

  def registrar_erro(contexto, erro)
    Rails.logger.error("[automacao][escuta] #{contexto} #{erro.class} em #{erro.backtrace&.first}")
  end

  def automacoes_do_gatilho(account_id, tipo)
    ::Autonomia::Automacao::Definicao.joins(:versao_ativa).where(account_id: account_id, ativa: true)
                                     .where("autonomia_automacao_versoes.receita -> 'gatilho' ->> 'tipo' = ?", tipo)
  end

  def esperando_condicao?(execucao)
    ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)&.fetch('tipo', nil) == 'esperar_ate'
  end

  # A mesma reserva da varredura (marca nova, só se continua esperando), mantendo o `due_at`: é o prazo do "esperar até",
  # que a rodada usa se a condição ainda não estiver cumprida.
  def reservar(execucao)
    marca = Time.current.floor(6)
    reservada = ::Autonomia::Automacao::Execucao.where(id: execucao.id, estado: 'esperando', due_at: execucao.due_at)
                                                .update_all(estado: 'andando', travada_em: marca, updated_at: marca) == 1 # rubocop:disable Rails/SkipsModelValidations
    ::Autonomia::Automacao::AvancarJob.perform_later(execucao.id, marca.iso8601(6)) if reservada
  end
end
