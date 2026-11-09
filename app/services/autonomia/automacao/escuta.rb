# O que a Automação livre ouve dos eventos da plataforma (#2414 F3, #2459). Quem chama é o AutomacaoListener.
#
# - `comecar`: o gatilho aconteceu (conversa criada, aberta, resolvida, mensagem criada). Cada automação ligada da
#   conta com esse gatilho tenta começar para a conversa (Partida, que confere quem ligou, a caixa, os filtros e a
#   cadeia).
# - `mensagem_criada`: o gatilho "mensagem.criada" e o despertar da conversa dela. A flag vem antes de carregar a
#   conversa: é o evento mais frequente da plataforma.
# - `evento_do_card`: o card criado, movido, ganho ou perdido (#2499, F6), que o emissor do CRM despacha também quando há
#   automação assinante (`assinante?`). Cada gatilho do evento começa com a marca da atividade e a etapa ou o funil.
#   Roda no EventoDoCardJob, não no listener: o erro sobe e o job tenta de novo sozinho, sem repetir os webhooks e os
#   avisos dos outros listeners do mesmo evento. A repetição é segura: a marca da atividade não deixa abrir duas.
# - `acordar`: a conversa (ou o contato dela) mudou. Quem espera num "esperar até" por ela, também o card cuja
#   conversa principal é ela, é reservado e confere a condição agora, em vez de esperar o prazo. A mensagem nova acorda
#   também quem espera pelo mesmo contato em outra conversa, no card ou no contato (#2680). Só o "esperar até": a ação
#   que espera uma nova tentativa e o "esperar" de tempo seguem o relógio.
# - `envio_atualizado`: a mensagem que a automação mandou foi entregue, lida ou falhou (#2680, `envio.situacao`).
# O card que mudou e o gatilho que aconteceu de novo durante a espera (lote 4, #2682) acordam pelo Despertador, que
# usa a mesma reserva daqui (`reservar`, `esperando_condicao?`).
#
# O gate é a flag do motor, lida da conta: conta sem o motor só lê a conta. Com o motor, uma consulta pela conta e pelo
# tipo do gatilho; não há cache, porque a lista muda a cada automação ligada ou desligada, e uma lista velha ligaria o
# que já foi desligado.
#
# Falha aqui vai para o log e não para as outras automações, nem o evento: o EventDispatcherJob tenta de novo, e
# repetiria os webhooks e avisos dos outros listeners. A exceção é o `evento_do_card`, que roda no job próprio e deixa
# o erro subir. Vale para o método inteiro (o Motor.ligado? e as consultas
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
    return if resposta_automatica?(alvo, tipo, mensagem)

    cada_automacao(alvo, tipo, dados) do |definicao|
      partir(definicao, alvo, tipo, mensagem: mensagem, evento: evento)
    rescue StandardError => e
      registrar_erro("não começou automacao=#{definicao.id} alvo=#{rotulo(alvo)}", e)
    end
  rescue StandardError => e
    registrar_erro("não ouviu gatilho=#{tipo} alvo=#{rotulo(alvo)}", e)
  end

  # A resposta automática de e-mail ("estou de férias", aviso do servidor) não é o contato falando: o MailPresenter a
  # marca pelo cabeçalho (Auto-Submitted, X-Autoreply), na mensagem e na conversa que ela abriu. Ela não começa
  # gatilho; senão "mensagem recebida → manda e-mail" giraria sem fim com o autoresponder do outro lado (G2), e a cadeia
  # não vê esse laço: a resposta chega como mensagem do contato. Vale para qualquer passo, como nas automações antigas
  # (AutomationRuleListener). A marca da conversa é de quando ela nasceu: na reaberta, quem decide é a última
  # mensagem recebida, porque o cliente de verdade pode reabrir a conversa que o autoresponder abriu.
  def resposta_automatica?(alvo, tipo, mensagem)
    return mensagem.auto_reply_email? if mensagem
    return false unless alvo.is_a?(::Conversation)

    case tipo
    when 'conversa.criada' then alvo.additional_attributes.to_h['auto_reply'].present?
    when 'conversa.aberta' then alvo.messages.incoming.reorder(created_at: :desc, id: :desc).first&.auto_reply_email? || false
    else false
    end
  end

  # As automações ligadas com o gatilho cujos parâmetros (etapa, funil) casam com os `dados` do evento.
  def cada_automacao(alvo, tipo, dados)
    automacoes_do_gatilho(alvo.account_id, tipo).includes(:account, :versao_ativa, :ligada_por).find_each do |definicao|
      yield definicao if ::Autonomia::Automacao::Gatilhos.casa?(definicao.versao_ativa.receita['gatilho'].to_h, dados)
    end
  end

  def partir(definicao, alvo, tipo, mensagem: nil, evento: nil)
    ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, mensagem: mensagem, evento: evento).call
  end

  # Para o log: o tipo e o id do banco, sem nome nem título (podem ser do cliente).
  def rotulo(alvo) = alvo ? "#{alvo.class.name}:#{alvo.id}" : 'nenhum'

  # Atividade (o histórico que a própria plataforma escreve) não é mensagem de ninguém. Nota privada conta: é mensagem
  # da equipe na conversa.
  def mensagem_criada(mensagem)
    return if mensagem.activity? || !::Autonomia::Automacao::Motor.ligado?(mensagem.account)

    comecar(mensagem.conversation, 'mensagem.criada', mensagem: mensagem)
    acordar(mensagem, [mensagem.conversation_id], contato_id: mensagem.conversation.contact_id)
  rescue StandardError => e
    registrar_erro("não ouviu mensagem=#{mensagem&.id}", e)
  end

  # A situação de uma mensagem que a automação mandou mudou (entregue, lida, falhou): a execução dela, se espera num
  # "esperar até", confere agora o `envio.situacao` (#2680). Só a mensagem com a marca da automação; a marca já diz a
  # execução, sem consulta para as outras.
  def envio_atualizado(mensagem, mudou)
    return unless mudou.to_h.key?('status')

    execucao = execucao_do_envio(mensagem)
    reservar(execucao) if execucao && esperando_condicao?(execucao)
  rescue StandardError => e
    registrar_erro("não acordou pelo envio mensagem=#{mensagem&.id}", e)
  end

  # A execução que espera, pela marca da mensagem; nil sem a marca ou com o motor desligado.
  def execucao_do_envio(mensagem)
    execucao_id = mensagem.content_attributes.to_h['execucao_id']
    return if execucao_id.blank? || !::Autonomia::Automacao::Motor.ligado?(mensagem.account)

    ::Autonomia::Automacao::Execucao.find_by(id: execucao_id, account_id: mensagem.account_id, estado: 'esperando')
  end

  # `registro`: o que mudou (conversa, contato ou mensagem); a conta sai dele aqui dentro, sob o rescue.
  # `conversa_ids`: lista ou subconsulta de ids das conversas. `contato_id`: a mensagem nova do cliente acorda também
  # quem espera por ele em outra conversa, no card dele ou no próprio contato (#2680: o e-mail abre outra conversa).
  def acordar(registro, conversa_ids, contato_id: nil)
    account = registro.account
    return unless ::Autonomia::Automacao::Motor.ligado?(account)

    acordar_quem_espera(::Autonomia::Automacao::EsperaDaConversa.de(account, conversa_ids, contato_id))
  rescue StandardError => e
    registrar_erro("não acordou #{registro.class.name}=#{registro&.id}", e)
  end

  # G32: a reunião do card foi marcada, remarcada ou cancelada. Quem espera no próprio card ("esperar até ter reunião
  # marcada") confere a condição agora, em vez de no fim do prazo. #2710: também quem espera em outro card do mesmo
  # contato, no contato ou numa conversa dele (`contato.tem_reuniao_marcada`).
  def acordar_o_card(card)
    espera = ::Autonomia::Automacao::EsperaDaReuniao
    acordar_quem_espera(espera.de(card.account_id, card.id), filtro: espera.method(:le_reuniao?))
  end

  # `filtro`: só reserva a execução que ele aceita (a reunião acorda só quem lê reunião).
  def acordar_quem_espera(execucoes, filtro: nil)
    execucoes.includes(:versao).find_each do |execucao|
      reservar(execucao) if esperando_condicao?(execucao) && (filtro.nil? || filtro.call(execucao))
    rescue StandardError => e
      registrar_erro("não acordou execucao=#{execucao.id}", e)
    end
  end

  # O listener só enfileira o evento do card, e só na conta com os gatilhos de card ligados. A cadeia em curso (que o
  # EventDispatcherJob retomou do evento) vai junto, para o laço e a profundidade valerem no job.
  def enfileirar_evento_do_card(dados, evento)
    account = Account.find_by(id: dados[:account_id])
    return unless account && ::Autonomia::Automacao::Motor.gatilhos?(account)

    ::Autonomia::Automacao::EventoDoCardJob.perform_later(dados.to_h.deep_stringify_keys.merge(cadeia_em_curso), evento)
  end

  def cadeia_em_curso
    cadeia = ::Autonomia::Automacao::Cadeia
    return {} unless cadeia.ativa?

    em_curso = { 'conta' => cadeia.conta_id, 'origens' => cadeia.origens, 'raiz' => cadeia.raiz }
    { ::Autonomia::Automacao::EventoDoCardJob::CHAVE_DA_CADEIA => em_curso }
  end

  # Um evento do card (#2499, F6), com os ids do emissor do CRM: cada gatilho que o evento dispara tenta começar, com a
  # marca da atividade. O card é relido do banco: o evento pode chegar depois de outra mudança. Card apagado no meio
  # (ou conta sem a flag agora) não é erro: não há o que começar. Qualquer outro erro sobe ao EventoDoCardJob.
  def evento_do_card(dados, evento)
    dados = dados.to_h.with_indifferent_access
    account = Account.find_by(id: dados[:account_id])
    return unless account && ::Autonomia::Automacao::Motor.gatilhos?(account)

    card = ::Crm::Card.find_by(id: dados[:card_id], account_id: account.id)
    return unless card

    mudou = dados[:changed_attributes].to_h.with_indifferent_access
    tipos = ::Autonomia::Automacao::Gatilhos::DO_EVENTO_DO_CARD.fetch(evento, [])
    tipos.each do |tipo|
      marca = ::Autonomia::Automacao::Gatilhos.marca_da_atividade(tipo, dados[:activity_id])
      cada_automacao(card, tipo, dados_do_card(tipo, card, mudou, dados[:activity_id])) { |definicao| partir(definicao, card, tipo, evento: marca) }
    end
    acordar_o_card(card) if tipos.any? { |tipo| ::Autonomia::Automacao::Gatilhos.de_reuniao?(tipo) }
  end

  # A etapa de onde o card saiu ou para onde entrou, e o funil, para os parâmetros do gatilho. O card criado traz a
  # etapa em que nasceu (stage_id); o movido, as duas pontas. A reunião (G32) traz também a página de agendamento.
  def dados_do_card(tipo, card, mudou, atividade_id = nil)
    case tipo
    when 'card.entrou_na_etapa' then { 'etapa_id' => mudou[:to_stage_id] || mudou[:stage_id] || card.stage_id }
    when 'card.saiu_da_etapa' then { 'etapa_id' => mudou[:from_stage_id] }
    else { 'funil_id' => mudou[:pipeline_id] || card.pipeline_id, **::Autonomia::Automacao::ReuniaoDaAtividade.do_gatilho(tipo, card, atividade_id) }
    end
  end

  # O emissor do CRM pergunta antes de despachar (#2499): a conta tem automação ligada com um gatilho que o evento
  # dispara, na etapa ou no funil do evento? A flag vem primeiro, lida da conta, sem consulta; depois um exists? pelo
  # índice (account_id, ativa), com o gatilho e o parâmetro lidos da receita na mesma consulta. O que o evento não traz
  # (o funil no ganho/perdido) não filtra: o job confere de novo com o card relido.
  #
  # Roda no after_commit do card: um erro aqui não pode quebrar o pedido de quem moveu o card, nem perder o evento. Em
  # erro, despacha assim mesmo (o job assíncrono decide) e loga só a classe.
  # A reunião (G32) assina também quando há execução esperando no card ou no contato dele (#2710): ela acorda para
  # conferir a condição.
  def assinante?(account, evento, mudou = {}, card_id: nil)
    tipos = tipos_ligados(account, evento)
    return false if tipos.blank?
    return true if ::Autonomia::Automacao::EsperaDaReuniao.no_card?(account, tipos, card_id)

    mudou = mudou.to_h.with_indifferent_access
    automacoes_do_gatilho(account.id, tipos).where(tipos.map { |tipo| gatilho_casa_sql(tipo, mudou) }.join(' OR ')).exists?
  rescue StandardError => e
    registrar_erro("gate do emissor falhou evento=#{evento} conta=#{account&.id}; despacha assim mesmo", e)
    true
  end

  # Os gatilhos que o evento dispara, só com a conta e a flag ligada.
  def tipos_ligados(account, evento)
    tipos = ::Autonomia::Automacao::Gatilhos::DO_EVENTO_DO_CARD[evento]
    tipos if tipos.present? && account.present? && ::Autonomia::Automacao::Motor.gatilhos?(account)
  end

  # "tipo = X AND (parâmetro vazio OR parâmetro = valor do evento)", com os valores escapados.
  def gatilho_casa_sql(tipo, mudou)
    nome, valor = parametro_do_evento(tipo, mudou)
    gatilho = "autonomia_automacao_versoes.receita -> 'gatilho'"
    return ::Autonomia::Automacao::Definicao.sanitize_sql_array(["(#{gatilho} ->> 'tipo' = ?)", tipo]) if valor.nil?

    ::Autonomia::Automacao::Definicao.sanitize_sql_array(
      ["(#{gatilho} ->> 'tipo' = ? AND (#{gatilho} ->> ? IS NULL OR #{gatilho} ->> ? = ?))", tipo, nome, nome, valor.to_s]
    )
  end

  # O parâmetro do gatilho e o valor que o evento traz, sem reler o card.
  def parametro_do_evento(tipo, mudou)
    case tipo
    when 'card.entrou_na_etapa' then ['etapa_id', mudou[:to_stage_id] || mudou[:stage_id]]
    when 'card.saiu_da_etapa' then ['etapa_id', mudou[:from_stage_id]]
    else ['funil_id', mudou[:pipeline_id]]
    end
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
