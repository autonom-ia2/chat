# O COMPARATIVO SEGURADO (#3258, flag `agente_le_no_meio_do_turno`, `LeituraNoTurno.ligada?`: fora da Lia, com a fila e a
# espera da fala). Com a entrega inteira (#3211), a fala que já começou termina mesmo quando o cliente escreve no meio
# dela (`FalaDaCadeia.comecada?`). O TEXTO continua assim. O comparativo do Seguro Viagem dessa fala (o PDF que sai
# depois do último pedaço, `CartoesDoTurno`) é outra coisa: o cliente que escreveu "minha esposa vai junto" recebia o PDF
# da cotação velha, e depois o da nova (teste C3, 26/11).
#
# SEGURAR: o último pedaço, ao ser postado sob o lock, confere o turno (o mesmo `current_turn?` que o 1º pedaço confere,
# com as mensagens que o turno leu). Turno mudou: o texto sai, e a âncora grava os comparativos como segurados (`CHAVE`,
# na mesma transação do post). O `CartoesDoTurno.da_ancora` os deixa fora da lista: o `EnviarCartoesJob` não os manda, e
# os outros cartões da âncora (voucher, mapa, contato) saem como sempre.
#
# NO FIM DO TURNO SEGUINTE deste agente (a cadeia que postou o último pedaço, a resposta que saiu inteira ou o sinal de
# silêncio), quem decide é um job próprio (`DecidirComparativoSeguradoJob`, só com ids, enfileirado por `decidir_depois`):
# a decisão tem o retry dela e nunca roda dentro do turno. Para cada segurado (ou solto que ainda não saiu) de uma fala
# anterior, sob o lock da âncora:
#   - a âncora foi encerrada (o job dos cartões desistiu dela): descartado (`ancora_encerrada`), com `cartao_nao_enviado`;
#   - o turno seguinte ENTREGA um comparativo (a resposta dele leva um, segurado ou não, que não foi descartado, numa âncora
#     não encerrada): descartado (`substituido_no_turno_seguinte`), com `cartao_descartado`. Cotar de novo sem mandar o
#     PDF não conta: o cliente ficaria sem nenhum;
#   - senão, o segurado é solto: sai pelo `EnviarCartoesJob` da âncora de sempre, com o token de sempre (uma vez só),
#     depois que a resposta do turno seguinte saiu (`depois_de`); sem resposta (silêncio), logo. O solto que ainda não
#     saiu volta à fila (o retry de uma decisão que morreu antes de enfileirar).
# O turno seguinte que não acontece (pessoa da equipe assumiu, conta desligada, dono mudou) não solta nada: o segurado
# fica como está e nunca sai sozinho. O que sai segue as guardas de sempre do `CartoesDoTurno#postar!`, que também
# confere de novo, sob o lock da conversa, que o comparativo não voltou a ficar fora da lista.
#
# POR QUE NA ÂNCORA: ela já guarda os cartões e a desistência (`autonomia_cartoes_encerrados`), sob o lock dela. Sem
# tabela nem Redis, e o retry do Sidekiq lê o mesmo estado: o pedaço já postado não segura de novo, e a decisão repetida
# não muda o que já foi decidido.
#
# A linha de cada decisão (`comparativo_segurado` acao=segurou|soltou|descartou|reenfileirou) leva só ids e rótulos.
module Autonomia::Agents::Operate::ComparativoSegurado
  CHAVE = 'autonomia_cartoes_segurados'.freeze
  SEGURADO = 'segurado'.freeze
  SOLTO = 'solto'.freeze
  DESCARTADO = 'descartado'.freeze
  SUBSTITUIDO = 'substituido_no_turno_seguinte'.freeze
  ENCERRADA = 'ancora_encerrada'.freeze
  NA_ANCORA = 'autonomia_cartoes'.freeze
  COMPARATIVO = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo

  module_function

  # O pedaço leva o comparativo e a chave vale para o agente nesta conversa. Sem comparativo, nem consulta a flag.
  def pode_segurar?(chunk, agent, conversation)
    tokens_do_comparativo(chunk.to_h['marca'].to_h).any? && ligada?(agent, conversation)
  end

  # O pedaço com os comparativos marcados como segurados, para a mensagem gravar junto com os cartões.
  def segurar(chunk)
    marca = chunk['marca'].to_h
    chunk.merge('marca' => marca.merge(CHAVE => tokens_do_comparativo(marca).index_with { { 'estado' => SEGURADO } }))
  end

  # A âncora recém-postada: a linha de cada comparativo que ela segurou.
  def segurou(ancora)
    estados(ancora).each { |token, valor| registrar(['segurou', nil], ancora, token) if valor.to_h['estado'] == SEGURADO }
  end

  # Fora da lista do `EnviarCartoesJob` agora: o segurado (espera o turno seguinte) e o descartado.
  def fora?(ancora, cartao)
    [SEGURADO, DESCARTADO].include?(estados(ancora).dig(cartao['token'], 'estado'))
  end

  # O solto espera a resposta do turno seguinte sair: a mensagem dela, ou nil (sem resposta, ou ela sumiu).
  def depois_de(ancora, cartao)
    id = estados(ancora).dig(cartao['token'], 'depois_de')
    id && ancora.conversation.messages.find_by(id: id)
  end

  # O turno da mensagem `reply_to_message_id` terminou: a decisão vai para o job dela. Sem a chave, nem enfileira.
  def decidir_depois(conversation, agent, reply_to_message_id)
    return if reply_to_message_id.blank? || !ligada?(agent, conversation)

    ::Autonomia::Agents::Operate::DecidirComparativoSeguradoJob.perform_later(conversation.id, agent.id, reply_to_message_id)
  end

  # No job: decide os segurados das falas anteriores deste agente.
  def no_fim_do_turno(conversation, agent, reply_to_message_id)
    return if reply_to_message_id.blank? || !ligada?(agent, conversation)

    ancoras = ancoras_anteriores(conversation, agent, reply_to_message_id)
    return if ancoras.empty?

    do_turno = mensagens_do_turno(conversation, reply_to_message_id)
    turno = { resposta: do_turno.last, entregou: entrega_comparativo?(do_turno) }
    ancoras.each do |ancora|
      estados(ancora).each { |token, valor| resolver(ancora, token, turno) unless valor.to_h['estado'] == DESCARTADO }
    end
  end

  def resolver(ancora, token, turno)
    decisao = decidir!(ancora, token, turno)
    return if decisao.nil?

    registrar(decisao, ancora, token)
    return rastro_do_descarte(ancora, decisao.last) if decisao.first == 'descartou'

    ::Autonomia::Agents::Operate::CartoesDoTurno.enfileirar(ancora)
  end

  # Sob o lock da conversa e, dentro dele, o da âncora (estado fresco). -> [a ação, o motivo do descarte] ou nil (nada
  # a fazer: já saiu, já decidido). O lock da conversa é o mesmo do `CartoesDoTurno#postar!`, na mesma ordem: o PDF
  # velho não sai enquanto a decisão o descarta.
  def decidir!(ancora, token, turno)
    ancora.conversation.with_lock do
      ancora.with_lock do
        estado = estados(ancora).dig(token, 'estado')
        cartoes = ::Autonomia::Agents::Operate::CartoesDoTurno.new(ancora)
        decisao(ancora, token, turno, estado, cartoes) if pendente?(estado, cartoes, token)
      end
    end
  end

  # O segurado, ou o solto que ainda não saiu numa âncora que o job dos cartões não encerrou.
  def pendente?(estado, cartoes, token)
    estado == SEGURADO || (estado == SOLTO && !cartoes.encerrado? && !cartoes.postado?('token' => token))
  end

  def decisao(ancora, token, turno, estado, cartoes)
    return descartar!(ancora, token, ENCERRADA) if estado == SEGURADO && cartoes.encerrado?
    return descartar!(ancora, token, SUBSTITUIDO) if turno[:entregou]
    return soltar!(ancora, token, turno[:resposta]) if estado == SEGURADO

    ['reenfileirou', nil]
  end

  def descartar!(ancora, token, motivo)
    gravar!(ancora, token, 'estado' => DESCARTADO, 'motivo' => motivo)
    ['descartou', motivo]
  end

  def soltar!(ancora, token, resposta)
    gravar!(ancora, token, 'estado' => SOLTO, 'depois_de' => resposta&.id)
    ['soltou', nil]
  end

  # Só esta chave, por merge, direto na coluna (sem callbacks nem `updated_at`), como `CartoesDoTurno#encerrar!`.
  def gravar!(ancora, token, estado)
    atributos = ancora.content_attributes.to_h
    ancora.update_column(:content_attributes, atributos.merge(CHAVE => estados(ancora).merge(token => estado))) # rubocop:disable Rails/SkipsModelValidations
  end

  # O rastro de sempre do cartão que não vai sair: `cartao_nao_enviado` para a âncora encerrada (como o job dos cartões),
  # `cartao_descartado` para o substituído.
  def rastro_do_descarte(ancora, motivo)
    atributos = ancora.content_attributes.to_h
    telemetria = ::Autonomia::Agents::Operate::TelemetriaDoTurno
    return telemetria.registrar(:cartao_nao_enviado, conversation_id: ancora.conversation_id, msg: ancora.id, motivo: motivo) if motivo == ENCERRADA

    ::Autonomia::Agents::Operate::CartoesDoTurno.descartados(conversation_id: ancora.conversation_id,
                                                             agent: atributos['autonomia_agent_id'],
                                                             msg: atributos['autonomia_reply_to_message_id'], motivo: motivo)
  end

  # O turno seguinte entrega um comparativo: alguma mensagem dele leva o cartão (segurado ou não), não descartado, numa
  # âncora que o job dos cartões não encerrou.
  def entrega_comparativo?(mensagens)
    mensagens.any? do |mensagem|
      atributos = mensagem.content_attributes.to_h
      atributos[::Autonomia::Agents::Operate::CartoesDoTurno::ENCERRADOS].blank? &&
        Array(atributos[NA_ANCORA]).any? do |cartao|
          COMPARATIVO.cartao?(cartao) && estados(mensagem).dig(cartao.to_h['token'], 'estado') != DESCARTADO
        end
    end
  end

  # As mensagens que este turno postou (os pedaços, ou a resposta inteira), em ordem; vazio quando ele calou.
  def mensagens_do_turno(conversation, reply_to_message_id)
    conversation.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', reply_to_message_id.to_i)
                .where('content_attributes::text LIKE ?', '%autonomia_reply_to_message_id%').reorder(:id)
                .select { |message| message.content_attributes.to_h['autonomia_reply_to_message_id'].to_s == reply_to_message_id.to_s }
  end

  # As âncoras deste agente com comparativo segurado ou solto, de turnos anteriores a este (a mensagem do cliente que
  # abriu cada uma é mais velha). Prefiltra por LIKE e confirma no hash, como `CartoesDoTurno.ancora_do_turno`. O
  # descartado não volta a ser lido.
  def ancoras_anteriores(conversation, agent, reply_to_message_id)
    conversation.messages.outgoing.where(sender_type: 'AgentBot').where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                .reorder(:id).select do |ancora|
      atributos = ancora.content_attributes.to_h
      atributos['autonomia_agent_id'].to_s == agent.id.to_s &&
        atributos['autonomia_reply_to_message_id'].to_i < reply_to_message_id.to_i &&
        estados(ancora).values.any? { |valor| valor.to_h['estado'] != DESCARTADO }
    end
  end

  def ligada?(agent, conversation)
    ::Autonomia::Agents::Operate::LeituraNoTurno.ligada?(agent, conversation)
  end

  def estados(ancora)
    valor = ancora&.content_attributes.to_h[CHAVE]
    valor.is_a?(Hash) ? valor : {}
  end

  def tokens_do_comparativo(marca)
    Array(marca[NA_ANCORA]).select { |cartao| COMPARATIVO.cartao?(cartao) }.filter_map { |cartao| cartao['token'] }
  end

  # `decisao`: [a ação, o motivo do descarte ou nil].
  def registrar(decisao, ancora, token)
    atributos = ancora.content_attributes.to_h
    cotacao = Array(atributos[NA_ANCORA]).find { |cartao| cartao.to_h['token'] == token }.to_h['chave']
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:comparativo_segurado, conversation_id: ancora.conversation_id,
                                                                                     agent: atributos['autonomia_agent_id'],
                                                                                     msg: atributos['autonomia_reply_to_message_id'],
                                                                                     acao: decisao.first, motivo: decisao.last,
                                                                                     ancora: ancora.id, cotacao: cotacao)
  end
end
