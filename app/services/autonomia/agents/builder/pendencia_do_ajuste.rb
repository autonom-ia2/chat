# #1428 (tema 6, parte 2) — a pendência do turno de AJUSTE no piloto e o "quer que eu desfaça?" do que o dono não
# pediu. Incluído no Builder junto com os outros módulos do ajuste; fora do piloto nada daqui roda.
#
# PENDÊNCIA: a pergunta aberta (`pergunta_pendente`) só sai quando o MODELO diz que a fala a resolveu
# (`pendencia_resolvida`), ou quando o código abre uma pergunta nova sobre o turno. Os turnos em laço (o modelo aplicou ou
# perguntou de novo sem resolvê-la, qualquer que seja o texto) contam; a pergunta do dono e os textos fixos não. No teto,
# a pendência não some calada: fica como contexto, sem a ordem de repetir (`pendencia_no_teto`).
#
# DESFAZER: quando parte do que entrou o dono não pediu, o state guarda `desfazer_pendente` (a versão de antes, as
# colunas, os resumos e o updated_at esperado). No turno seguinte, se o MODELO leu que o dono aceitou
# (`desfazer_o_nao_pedido`), o código desfaz pela mesma trava do desfazer automático. Recusa ou pedido novo limpam a chave.
module Autonomia::Agents::Builder::PendenciaDoAjuste
  TETO_DE_TURNOS_DA_PENDENCIA = 3

  # As descrições dos dois campos do schema do ajuste que o modelo preenche sobre a pendência (AjustePorLista::SCHEMA).
  PENDENCIA_RESOLVIDA_DESCRIPTION =
    'So vale quando o contexto interno traz uma PERGUNTA PENDENTE sua. true quando a ultima fala do dono responde ' \
    'essa pergunta, ou quando ela nao vale mais porque o dono mudou de assunto de vez ou a desfez. false quando ela ' \
    'continua sem resposta (o dono pediu outra coisa sem responder) ou quando nao ha pergunta pendente. Se voce ' \
    'repetir a pergunta em next_question, deixe false.'.freeze

  DESFAZER_DESCRIPTION =
    'So vale quando a PERGUNTA PENDENTE sua oferece desfazer algo que o dono nao pediu ("quer que eu desfaca?"). ' \
    'true quando a ultima fala do dono aceita desfazer; false quando recusa, quando pede outra coisa sem responder ' \
    'ou quando nao ha essa pergunta. Com true, a plataforma desfaz: nao liste isso em mudancas.'.freeze

  private

  # A pendência de antes do turno, a menos que o MODELO diga que a fala a resolveu. O código nunca a apaga sozinho.
  def pendencia_mantida(parsed)
    resolvida?(parsed) ? '' : @pendencia_anterior.to_s
  end

  def resolvida?(parsed)
    parsed.to_h['pendencia_resolvida'] == true
  end

  # -> as chaves da pendência no state. `origem`: :modelo (pergunta dele), :mantida (a anterior) ou :codigo (pergunta
  # nova que o código abre sobre o turno, zera). `laco`: o turno conta para o teto (o modelo aplicou ou perguntou de
  # novo sem resolver a pendência).
  def pendencia_no_estado(pendencia, parsed, origem:, laco:)
    pendencia = pendencia.to_s
    nova = pendencia.blank? || @pendencia_anterior.blank? || origem == :codigo || resolvida?(parsed)
    return { 'pergunta_pendente' => pendencia, 'pendencia_turnos' => 0, 'pendencia_no_teto' => false } if nova

    turnos = laco ? @turnos_da_pendencia + 1 : @turnos_da_pendencia
    { 'pergunta_pendente' => pendencia, 'pendencia_turnos' => turnos,
      'pendencia_no_teto' => turnos >= TETO_DE_TURNOS_DA_PENDENCIA }
  end

  # No teto, a pendência segue como contexto, sem a ordem de repetir.
  def pendencia_no_teto_context(pergunta)
    'CONTEXTO INTERNO (não é fala do usuário). PERGUNTA QUE FICOU SEM RESPOSTA (já repetida o bastante; NÃO a ' \
      "repita e não a cobre): \"#{pergunta}\". Use só como contexto. Se a fala do dono a responder, aplique e marque " \
      'pendencia_resolvida=true.'
  end

  # O "sim, desfaça": o código desfaz o que ficou guardado no turno anterior, com a mesma trava e o updated_at esperado.
  def desfazer_o_pendente!(token, parsed)
    dados = @desfazer_pendente
    return unless dados.is_a?(Hash) && parsed['desfazer_o_nao_pedido'] == true

    ok = @thread.agent.desfazer_do_construtor!(
      versoes: { antes: dados['versao_antes_id'], aplicacao: dados['versao_id'] }, colunas: Array(dados['colunas']),
      chaves: Array(dados['chaves']), esperado: dados['agente_updated_at'], geracao: { thread_id: @thread.id, token: token }
    )
    textos = Autonomia::Agents::Builder::TextosDoAjuste
    @mensagens_iniciais = [ok ? textos.desfiz(dados['itens'], idioma_do_ajuste) : textos.nao_desfiz(dados['itens'], idioma_do_ajuste)]
    @resultado_do_desfazer = ok ? :desfez : :recusado
  end

  # O turno foi só o "sim, desfaça" (nenhum pedido novo): fecha com o texto do desfazer.
  def fechar_so_o_desfazer!(token, parsed)
    perguntar!(token, parsed, [], { 'so_pergunta' => false, 'applied' => @resultado_do_desfazer == :desfez }
                                    .merge(pendencia_no_estado('', parsed, origem: :codigo, laco: false)))
  end

  # O que guardar para um "sim, desfaça" no turno seguinte (só quando parte do que entrou o dono não pediu).
  def desfazer_pendente_de(dados, conferencia)
    sem_pedido = Array(conferencia['sem_pedido'])
    return if sem_pedido.empty?

    pedidos = Array(conferencia['itens']).reject { |item| sem_pedido.include?(item) }
    colunas, chaves = colunas_e_chaves(regras_do_ajuste.campos(sem_pedido))
    colunas_pedidas, chaves_pedidas = colunas_e_chaves(regras_do_ajuste.campos(pedidos))
    { 'versao_antes_id' => dados['versao_antes_id'], 'versao_id' => dados.dig('correcao', 'versao_id') || dados['versao_id'],
      'colunas' => colunas - colunas_pedidas, 'chaves' => chaves - chaves_pedidas, 'agente_updated_at' => dados['agente_updated_at'],
      'itens' => sem_pedido.map { |item| item.slice('pedido', 'campo', 'resumo') } }
  end
end
