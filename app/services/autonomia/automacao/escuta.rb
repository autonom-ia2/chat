# O que a Automação livre ouve dos eventos da plataforma (#2414 F3, #2459). Quem chama é o AutomacaoListener.
#
# - `comecar`: o gatilho aconteceu (conversa criada, aberta, resolvida, mensagem criada). Cada automação ligada da
#   conta com esse gatilho tenta começar para a conversa (Partida, que confere quem ligou, a caixa, os filtros e a
#   cadeia).
# - `mensagem_criada`: o gatilho "mensagem.criada" e o despertar da conversa dela. A flag vem antes de carregar a
#   conversa: é o evento mais frequente da plataforma.
# - `evento_do_card`: o card criado, movido, ganho ou perdido (#2499, F6), que o emissor do CRM despacha também quando há
#   automação assinante (`assinante?`). Cada gatilho do evento começa com a marca da atividade e a etapa ou o funil.
# - `acordar`: a conversa (ou o contato dela) mudou. Quem espera num "esperar até" por ela é reservado e confere a
#   condição agora, em vez de esperar o prazo. Só o "esperar até": a ação que espera uma nova tentativa e o "esperar"
#   de tempo seguem o relógio.
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

  # `alvo`: a conversa, o card ou o contato do gatilho (Gatilhos). `evento`: a marca única do fato. `dados`: o que o
  # evento traz para os parâmetros do gatilho (a etapa, o funil).
  def comecar(alvo, tipo, mensagem: nil, evento: nil, dados: {})
    return unless alvo && ::Autonomia::Automacao::Motor.ligado?(alvo.account)

    automacoes_do_gatilho(alvo.account_id, tipo).includes(:account, :versao_ativa, :ligada_por).find_each do |definicao|
      next unless ::Autonomia::Automacao::Gatilhos.casa?(definicao.versao_ativa.receita['gatilho'].to_h, dados)

      ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, mensagem: mensagem, evento: evento).call
    rescue StandardError => e
      registrar_erro("não começou automacao=#{definicao.id} alvo=#{rotulo(alvo)}", e)
    end
  rescue StandardError => e
    registrar_erro("não ouviu gatilho=#{tipo} alvo=#{rotulo(alvo)}", e)
  end

  # Para o log: o tipo e o id do banco, sem nome nem título (podem ser do cliente).
  def rotulo(alvo) = alvo ? "#{alvo.class.name}:#{alvo.id}" : 'nenhum'

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

    ::Autonomia::Automacao::Execucao.where(account_id: account.id, alvo_type: 'Conversation', alvo_id: conversa_ids, estado: 'esperando')
                                    .includes(:versao).find_each do |execucao|
      reservar(execucao) if esperando_condicao?(execucao)
    rescue StandardError => e
      registrar_erro("não acordou execucao=#{execucao.id}", e)
    end
  rescue StandardError => e
    registrar_erro("não acordou #{registro.class.name}=#{registro&.id}", e)
  end

  # Um evento do card (#2499, F6), com os ids do emissor do CRM: cada gatilho que o evento dispara tenta começar, com a
  # marca da atividade. O card é relido do banco: o evento pode chegar depois de outra mudança.
  def evento_do_card(dados, evento)
    dados = dados.to_h.with_indifferent_access
    account = Account.find_by(id: dados[:account_id])
    return unless account && ::Autonomia::Automacao::Motor.gatilhos?(account)

    card = ::Crm::Card.find_by(id: dados[:card_id], account_id: account.id)
    return unless card

    mudou = dados[:changed_attributes].to_h.with_indifferent_access
    ::Autonomia::Automacao::Gatilhos::DO_EVENTO_DO_CARD.fetch(evento, []).each do |tipo|
      comecar(card, tipo, evento: ::Autonomia::Automacao::Gatilhos.marca_da_atividade(tipo, dados[:activity_id]),
                          dados: dados_do_card(tipo, card, mudou))
    end
  rescue StandardError => e
    registrar_erro("não ouviu evento=#{evento} card=#{dados && dados[:card_id]}", e)
  end

  # A etapa de onde o card saiu ou para onde entrou, e o funil, para os parâmetros do gatilho. O card criado traz a
  # etapa em que nasceu (stage_id); o movido, as duas pontas.
  def dados_do_card(tipo, card, mudou)
    case tipo
    when 'card.entrou_na_etapa' then { 'etapa_id' => mudou[:to_stage_id] || mudou[:stage_id] || card.stage_id }
    when 'card.saiu_da_etapa' then { 'etapa_id' => mudou[:from_stage_id] }
    else { 'funil_id' => mudou[:pipeline_id] || card.pipeline_id }
    end
  end

  # O emissor do CRM pergunta antes de despachar (#2499): a conta tem automação ligada com um gatilho que o evento
  # dispara? A flag vem primeiro, lida da conta, sem consulta; depois um exists? pelo índice (account_id, ativa).
  def assinante?(account, evento)
    tipos = ::Autonomia::Automacao::Gatilhos::DO_EVENTO_DO_CARD[evento]
    return false if tipos.blank? || account.blank? || !::Autonomia::Automacao::Motor.gatilhos?(account)

    automacoes_do_gatilho(account.id, tipos).exists?
  end

  def registrar_erro(contexto, erro)
    Rails.logger.error("[automacao][escuta] #{contexto} #{erro.class} em #{erro.backtrace&.first}")
  end

  # `tipo`: um tipo ou a lista dos que o evento dispara.
  def automacoes_do_gatilho(account_id, tipo)
    ::Autonomia::Automacao::Definicao.joins(:versao_ativa).where(account_id: account_id, ativa: true)
                                     .where("autonomia_automacao_versoes.receita -> 'gatilho' ->> 'tipo' IN (?)", Array(tipo))
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
