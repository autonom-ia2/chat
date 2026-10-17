# #1428 (tema 6, parte 2) — o fim do turno de AJUSTE no piloto: o que não foi pedido volta a ser como era, e o que vai
# ao dono, a pendência e o state. Incluído no Builder junto com AjusteConferido e FechamentoDoAjuste.
#
# O QUE NÃO FOI PEDIDO: os itens são agrupados pelo `pedido` que o próprio Construtor escreveu (comparação do texto,
# sem ler linguagem). Um item com o mesmo `pedido` de um item pedido é destino secundário desse pedido (a tabela manda
# "no máximo 2 frases" para o tom E a instrução) e nunca é desfeito. Só quando TODOS os itens estão sem pedido o código
# desfaz sozinho, sob a trava, com o valor da versão de antes, e o turno fecha como não aplicado. Quando só parte está
# sem pedido, tudo fica aplicado e o dono decide: "também mudei …, quer que eu desfaça?" vira pendência, e a resposta
# dele desfaz pelo caminho normal do ajuste.
#
# Ao dono só vão textos do código e dos campos próprios do Construtor (`resposta_ao_dono`, a pergunta de esclarecimento
# dele): nunca um `next_question` que afirme aplicação. Com aviso de desfecho ou com falta apontada, needs_more_info.
module Autonomia::Agents::Builder::DesfechoDoAjuste
  # Desfechos da correção que só avisam o dono (nada a perguntar).
  AVISOS_DO_DESFECHO = { superado: :correcao_superada, apagado: :agente_apagado, agente_mudou: :agente_mudou }.freeze
  SEM_PENDENCIA = %i[manual superado apagado agente_mudou nao_conferido].freeze

  private

  # -> a conferência com `sem_pedido` (os itens que o dono não pediu, quando é só parte) ou `desfeito`
  # ({ campos, ok }, quando era tudo e o código desfez).
  def desfazer_o_que_nao_foi_pedido(token, dados, conferencia)
    itens = Array(conferencia['itens'])
    sem_pedido = itens_sem_pedido(itens)
    return conferencia if sem_pedido.empty?
    return conferencia.merge('sem_pedido' => sem_pedido) if sem_pedido.size < itens.size

    conferencia.merge('desfeito' => { 'campos' => regras_do_ajuste.campos(itens), 'ok' => desfazer!(token, dados, itens) })
  end

  # Sem pedido do dono E sem o mesmo `pedido` de um item pedido (destino secundário do mesmo pedido conta como pedido).
  def itens_sem_pedido(itens)
    pedidos = itens.reject { |item| item['pedido_pelo_dono'] == false }.pluck('pedido')
    itens.select { |item| item['pedido_pelo_dono'] == false && pedidos.exclude?(item['pedido']) }
  end

  # As colunas e as chaves do config destes campos.
  def colunas_e_chaves(campos)
    [campos.flat_map { |campo| regras_do_ajuste::COLUNAS_POR_CAMPO.fetch(campo, []) }.uniq.map(&:to_s),
     campos.filter_map { |campo| regras_do_ajuste::CHAVES_DA_CONFIG_POR_CAMPO[campo] }]
  end

  def desfazer!(token, dados, itens)
    colunas, chaves = colunas_e_chaves(regras_do_ajuste.campos(itens))
    versoes = { antes: dados['versao_antes_id'], aplicacao: dados.dig('correcao', 'versao_id') || dados['versao_id'] }
    @thread.agent.desfazer_do_construtor!(versoes: versoes, colunas: colunas, chaves: chaves, esperado: dados['agente_updated_at'],
                                          geracao: { thread_id: @thread.id, token: token })
  end

  # Fecha o turno aplicado. Ao dono vão, nesta ordem: a resposta à pergunta dele, o aviso do desfecho e a pendência.
  def fechar_ajuste!(token, dados, conferencia, desfecho)
    resposta = dados.dig('correcao', 'resposta') || dados['resposta'].to_h
    return fechar_desfeito!(token, resposta, conferencia) if conferencia.dig('desfeito', 'ok') == true

    mensagens, pendencia, aviso = conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    estado = estado_do_ajuste(resposta.merge('needs_more_info' => precisa?(pendencia, aviso, conferencia),
                                             'next_question' => mensagens.last.to_s))
             .merge(estado_aplicado(dados, conferencia, pendencia.presence || pendencia_mantida(resposta)))
    mensagens.each { |mensagem| persist_assistant_turn!(mensagem) } if @thread.mark_ready!(token, state: estado)
    log_do_ajuste(conferencia, desfecho)
  end

  # -> [mensagens ao dono, pendência, aviso]. A pergunta do que o dono não pediu soma-se à pendência do turno.
  def conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    nao_pedido = conferencia['sem_pedido'].presence &&
                 Autonomia::Agents::Builder::TextosDoAjuste.pergunta_do_nao_pedido(conferencia['sem_pedido'], idioma_do_ajuste)
    pendencia = [pergunta_do_modelo(resposta) || pendencia_da_conferencia(conferencia, desfecho), nao_pedido]
                .compact_blank.join(' ').presence
    aviso = aviso_do_desfecho(desfecho, dados, conferencia)
    [[resposta['resposta_ao_dono'].to_s.strip, aviso, pendencia].compact_blank, pendencia, aviso]
  end

  def estado_aplicado(dados, conferencia, pendencia)
    { 'applied' => true, 'truncated_fields' => Array(dados['campos_truncados']) | @campos_truncados, 'so_pergunta' => false,
      'conferencia' => conferencia, 'ajuste_em_curso' => nil }.merge(pendencia_no_estado(pendencia))
  end

  # Com aviso de desfecho, pendência ou qualquer falta apontada, a conversa segue aberta.
  def precisa?(pendencia, aviso, conferencia)
    pendencia.present? || aviso.present? || conferencia['falta'] == true
  end

  # Tudo o que entrou não tinha sido pedido e foi desfeito: o turno não aplicou nada, e o dono sabe o que foi desfeito.
  def fechar_desfeito!(token, resposta, conferencia)
    texto = Autonomia::Agents::Builder::TextosDoAjuste.desfiz_o_nao_pedido(conferencia['itens'], idioma_do_ajuste)
    sem_mudanca!(token, resposta, { 'conferencia' => conferencia }, texto: texto)
    log_do_ajuste(conferencia, :desfeito)
  end

  def aviso_do_desfecho(desfecho, dados, conferencia)
    textos = Autonomia::Agents::Builder::TextosDoAjuste
    return textos.nao_desfiz(conferencia['itens'], idioma_do_ajuste) if conferencia.dig('desfeito', 'ok') == false

    if desfecho == :nao_conferido
      pedidos = textos.lista(dados.dig('correcao', 'mudancas'), 'pedido')
      return texto_do_ajuste(:nao_conferido, pedidos: pedidos)
    end

    AVISOS_DO_DESFECHO[desfecho] && texto_do_ajuste(AVISOS_DO_DESFECHO[desfecho])
  end

  def pendencia_da_conferencia(conferencia, desfecho)
    return if SEM_PENDENCIA.include?(desfecho)

    textos = Autonomia::Agents::Builder::TextosDoAjuste
    falta = conferencia['falta'] && textos.pergunta_do_que_faltou(conferencia, idioma_do_ajuste, explicacao: @explicacao_da_correcao)
    return falta if falta

    textos.pergunta_do_conflito(Array(conferencia['itens']), idioma_do_ajuste) if conferencia['conflito']
  end

  # A pergunta que o próprio Construtor fez sobre o que ficou vago.
  def pergunta_do_modelo(resposta)
    return unless resposta.to_h['needs_more_info'] == true

    resposta['next_question'].to_s.strip.presence
  end

  # Só metadados: quantas chamadas e conferências, quanto duraram e o desfecho da correção. Nunca conteúdo.
  def log_do_ajuste(conferencia, desfecho)
    Rails.logger.info(
      "[autonomia][builder] ajuste thread=#{@thread.id} calls=#{@calls.size} conferencias=#{@conferencias_ms.size} " \
      "conferencias_ms=#{@conferencias_ms.join(',')} correcao=#{conferencia['correcao'] == true} " \
      "desfecho=#{desfecho || '-'} conferencia=#{conferencia['erro'] || 'ok'} " \
      "falta=#{conferencia['falta'] == true} conflito=#{conferencia['conflito'] == true} " \
      "desfeito=#{conferencia.dig('desfeito', 'campos').to_a.join(',')} sem_pedido=#{Array(conferencia['sem_pedido']).size}"
    )
  end
end
