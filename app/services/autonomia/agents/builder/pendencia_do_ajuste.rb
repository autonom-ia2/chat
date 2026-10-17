# #1428 (tema 6, parte 2) — a pendência do turno de AJUSTE no piloto. Incluído no Builder junto com os outros módulos
# do ajuste; fora do piloto nada daqui roda.
#
# PENDÊNCIA: a pergunta aberta (`pergunta_pendente`) só sai quando o MODELO diz que a fala a resolveu
# (`pendencia_resolvida`), ou quando o código abre uma pergunta nova sobre o turno. Os turnos em laço (o modelo aplicou ou
# perguntou de novo sem resolvê-la, qualquer que seja o texto) contam; a pergunta do dono e os textos fixos não. No teto,
# a pendência não some calada: fica como contexto, sem a ordem de repetir (`pendencia_no_teto`).
module Autonomia::Agents::Builder::PendenciaDoAjuste
  TETO_DE_TURNOS_DA_PENDENCIA = 3

  # A descrição do campo do schema do ajuste que o modelo preenche sobre a pendência (AjustePorLista::SCHEMA).
  PENDENCIA_RESOLVIDA_DESCRIPTION =
    'So vale quando o contexto interno traz uma PERGUNTA PENDENTE sua. true quando a ultima fala do dono responde ' \
    'essa pergunta, ou quando ela nao vale mais porque o dono mudou de assunto de vez ou a desfez. false quando ela ' \
    'continua sem resposta (o dono pediu outra coisa sem responder) ou quando nao ha pergunta pendente. Se voce ' \
    'repetir a pergunta em next_question, deixe false.'.freeze

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

  # #1428 — o nome e o cartão que o dono vê, atuais. O contexto do ajuste (adjust_context, de todas as contas) não os
  # traz, e no piloto o item `instruction` grava o cartão junto: sem vê-lo, o modelo o devolvia vazio e o turno travava
  # (eval de 17/10). Só no ajuste do piloto; os dois são texto que o dono vê, não sigilo.
  def contexto_do_cartao
    agent = @thread.agent
    # Em JSON, como o retrato: uma quebra de linha no nome não vira uma linha de contexto nova.
    texto = "CONTEXTO INTERNO (nao e fala do usuario). Campos que o dono ve, atuais (devolva iguais o que nao for pedido):\n" \
            "#{JSON.generate('name' => agent.name.to_s, 'human_card' => agent.human_card.to_s)}"
    { role: 'user', content: [{ type: 'input_text', text: texto }] }
  end

  # O valor de antes do que o dono não pediu, para a conferência (numa mensagem própria, fora da fala do dono). Sem o
  # andaime: a conferência não precisa dele para julgar.
  def valores_antes_do_nao_pedido
    valores_de_antes(com_andaime: false).map { |campo, valor| "#{campo}: #{Array.wrap(valor).join(' | ')}" }.join("\n")
  end

  # Os valores de antes, lidos da versão, dos campos que o último ajuste mudou sem o dono pedir.
  def valores_de_antes(com_andaime:)
    dados = @thread.state.to_h['nao_pedido_anterior']
    return {} unless dados.is_a?(Hash)

    versao = @thread.agent.instruction_versions.find_by(id: dados['versao_antes_id'])
    return {} if versao.nil?

    antes = retrato_da_versao(versao).merge('scaffold' => versao.metadata.to_h.dig('agente', 'scaffold').to_s)
    campos = campos_com_o_que_acompanha(dados['campos'])
    campos -= ['scaffold'] unless com_andaime
    campos.index_with { |campo| antes[campo] }
  end

  # #1428 — o turno anterior mudou campos que o dono não pediu e o avisou ("é só me dizer o que tirar"). O Construtor
  # recebe, como CONTEXTO INTERNO, o valor de antes desses campos, lido da versão: um "tira isso" volta ao original. A
  # instrução vai como já vai a configuração atual no contexto do ajuste (mesmo sigilo, §11). Vale só para este turno.
  def contexto_do_nao_pedido
    valores = valores_de_antes(com_andaime: true)
    return [] if valores.empty?

    linhas = valores.map { |campo, valor| "#{campo}: #{Array.wrap(valor).join(' | ')}" }
    texto = ['CONTEXTO INTERNO (nao e fala do usuario). O ultimo ajuste tambem mudou, sem o dono pedir, os campos ' \
             'abaixo, e o dono foi avisado. Se ele pedir para tirar ou voltar, use o valor antes do ultimo ajuste:', *linhas]
    [{ role: 'user', content: [{ type: 'input_text', text: texto.join("\n") }] }]
  end

  # A instrução grava junto o andaime e o cartão: os três voltam juntos.
  def campos_com_o_que_acompanha(campos)
    campos = Array(campos)
    campos.include?('instruction') ? (campos + %w[scaffold human_card]).uniq : campos
  end

  # No teto, a pendência segue como contexto, sem a ordem de repetir.
  def pendencia_no_teto_context(pergunta)
    'CONTEXTO INTERNO (não é fala do usuário). PERGUNTA QUE FICOU SEM RESPOSTA (já repetida o bastante; NÃO a ' \
      "repita e não a cobre): \"#{pergunta}\". Use só como contexto. Se a fala do dono a responder, aplique e marque " \
      'pendencia_resolvida=true.'
  end
end
