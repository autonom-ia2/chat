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
# NO FIM DO TURNO SEGUINTE deste agente (`no_fim_do_turno`: a cadeia que postou o último pedaço, a resposta que saiu
# inteira ou o sinal de silêncio), cada segurado de uma fala anterior:
#   - descartado (`substituido_no_turno_seguinte`), quando há cotação mais nova deste agente na conversa: o turno
#     seguinte cotou de novo e o PDF dele é o que vale;
#   - solto, senão: sai pelo `EnviarCartoesJob` da âncora de sempre, com o token de sempre (uma vez só), depois que a
#     resposta do turno seguinte saiu (`depois_de`); sem resposta (silêncio), logo.
# O turno seguinte que não acontece (pessoa da equipe assumiu, conta desligada, dono mudou) não solta nada: o segurado
# fica como está e nunca sai sozinho. O que sai segue as guardas de sempre do `CartoesDoTurno#postar!`.
#
# POR QUE NA ÂNCORA: ela já guarda os cartões e a desistência (`autonomia_cartoes_encerrados`), sob o lock dela. Sem
# tabela nem Redis, e o retry do Sidekiq lê o mesmo estado: o pedaço já postado não segura de novo, e o segurado solto
# que ainda não saiu é enfileirado de novo no fim do próximo turno (o job é idempotente pelo token).
#
# A linha de cada decisão (`comparativo_segurado` acao=segurou|soltou|descartou|reenfileirou) leva só ids e o rótulo.
module Autonomia::Agents::Operate::ComparativoSegurado
  CHAVE = 'autonomia_cartoes_segurados'.freeze
  SEGURADO = 'segurado'.freeze
  SOLTO = 'solto'.freeze
  DESCARTADO = 'descartado'.freeze
  SUBSTITUIDO = 'substituido_no_turno_seguinte'.freeze
  NA_ANCORA = 'autonomia_cartoes'.freeze
  COMPARATIVO = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo

  module_function

  # O pedaço leva o comparativo e a chave vale para o agente nesta conversa. Sem comparativo, nem consulta a flag.
  def pode_segurar?(chunk, agent, conversation)
    tokens_do_comparativo(chunk.to_h['marca'].to_h).any? && ::Autonomia::Agents::Operate::LeituraNoTurno.ligada?(agent, conversation)
  end

  # O pedaço com os comparativos marcados como segurados, para a mensagem gravar junto com os cartões.
  def segurar(chunk)
    marca = chunk['marca'].to_h
    chunk.merge('marca' => marca.merge(CHAVE => tokens_do_comparativo(marca).index_with { { 'estado' => SEGURADO } }))
  end

  # A âncora recém-postada: a linha de cada comparativo que ela segurou.
  def segurou(ancora)
    estados(ancora).each { |token, valor| registrar('segurou', ancora, token) if valor.to_h['estado'] == SEGURADO }
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

  # O turno da mensagem `reply_to_message_id` terminou: decide os segurados das falas anteriores deste agente.
  def no_fim_do_turno(conversation, agent, reply_to_message_id)
    return if reply_to_message_id.blank? || !::Autonomia::Agents::Operate::LeituraNoTurno.ligada?(agent, conversation)

    ancoras = ancoras_anteriores(conversation, agent, reply_to_message_id)
    return if ancoras.empty?

    resposta = resposta_do_turno(conversation, reply_to_message_id)
    ancoras.each do |ancora|
      estados(ancora).each { |token, valor| resolver(ancora, token, agent, resposta) unless valor.to_h['estado'] == DESCARTADO }
    end
  end

  def resolver(ancora, token, agent, resposta)
    acao = decidir!(ancora, token, agent, resposta)
    return if acao.nil?

    registrar(acao, ancora, token)
    return descartado(ancora) if acao == 'descartou'

    ::Autonomia::Agents::Operate::CartoesDoTurno.enfileirar(ancora)
  end

  # Sob o lock da âncora (estado fresco): o segurado vira descartado ou solto; o solto que ainda não saiu (o retry de um
  # fim de turno que morreu antes de enfileirar) volta à fila. -> a ação, ou nil.
  def decidir!(ancora, token, agent, resposta)
    ancora.with_lock do
      estado = estados(ancora).dig(token, 'estado')
      if estado == SEGURADO && substituido?(ancora, token, agent)
        gravar!(ancora, token, 'estado' => DESCARTADO)
        'descartou'
      elsif estado == SEGURADO
        gravar!(ancora, token, 'estado' => SOLTO, 'depois_de' => resposta&.id)
        'soltou'
      elsif estado == SOLTO && ainda_por_sair?(ancora, token)
        'reenfileirou'
      end
    end
  end

  # Há cotação deste agente na conversa mais nova que a do comparativo segurado.
  def substituido?(ancora, token, agent)
    chave = Array(ancora.content_attributes.to_h[NA_ANCORA]).find { |cartao| cartao.to_h['token'] == token }.to_h['chave']
    ultima = ::Autonomia::Agents::CotacaoDeViagem.ultima_da_conversa(ancora.conversation_id, agent.id)
    ultima.present? && ultima.id > chave.to_i
  end

  def ainda_por_sair?(ancora, token)
    cartoes = ::Autonomia::Agents::Operate::CartoesDoTurno.new(ancora)
    !cartoes.encerrado? && !cartoes.postado?('token' => token)
  end

  # Só esta chave, por merge, direto na coluna (sem callbacks nem `updated_at`), como `CartoesDoTurno#encerrar!`.
  def gravar!(ancora, token, estado)
    atributos = ancora.content_attributes.to_h
    ancora.update_column(:content_attributes, atributos.merge(CHAVE => estados(ancora).merge(token => estado))) # rubocop:disable Rails/SkipsModelValidations
  end

  def descartado(ancora)
    ::Autonomia::Agents::Operate::CartoesDoTurno.descartados(conversation_id: ancora.conversation_id,
                                                             agent: ancora.content_attributes.to_h['autonomia_agent_id'],
                                                             msg: ancora.content_attributes.to_h['autonomia_reply_to_message_id'],
                                                             motivo: SUBSTITUIDO)
  end

  # A última mensagem que este turno postou (o último pedaço, ou a resposta inteira), ou nil quando ele calou.
  def resposta_do_turno(conversation, reply_to_message_id)
    conversation.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', reply_to_message_id.to_i)
                .where('content_attributes::text LIKE ?', '%autonomia_reply_to_message_id%').reorder(id: :desc)
                .find { |message| message.content_attributes.to_h['autonomia_reply_to_message_id'].to_s == reply_to_message_id.to_s }
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

  def estados(ancora)
    valor = ancora&.content_attributes.to_h[CHAVE]
    valor.is_a?(Hash) ? valor : {}
  end

  def tokens_do_comparativo(marca)
    Array(marca[NA_ANCORA]).select { |cartao| COMPARATIVO.cartao?(cartao) }.filter_map { |cartao| cartao['token'] }
  end

  def registrar(acao, ancora, token)
    atributos = ancora.content_attributes.to_h
    cotacao = Array(atributos[NA_ANCORA]).find { |cartao| cartao.to_h['token'] == token }.to_h['chave']
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:comparativo_segurado, conversation_id: ancora.conversation_id,
                                                                                     agent: atributos['autonomia_agent_id'],
                                                                                     msg: atributos['autonomia_reply_to_message_id'],
                                                                                     acao: acao, ancora: ancora.id, cotacao: cotacao)
  end
end
