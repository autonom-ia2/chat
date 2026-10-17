# #1428 (tema 6, parte 2) — o fim do turno de AJUSTE no piloto: o que não foi pedido volta a ser como era, e o que vai
# ao dono, a pendência e o state. Incluído no Builder junto com AjusteConferido e FechamentoDoAjuste.
#
# O QUE NÃO FOI PEDIDO FICA IDÊNTICO: um item da lista que a conferência diz que o dono não pediu é desfeito, sob a
# trava, com o valor da versão de antes (só as colunas que nenhum item pedido também escreve). Se nada pedido entrou, o
# turno fecha como sem mudança e a versão da aplicação sai da lista; se entrou parte, o dono recebe o que entrou. Não se
# pergunta ao dono para desfazer o que ele não pediu.
#
# Ao dono só vão textos do código e dos campos próprios do Construtor (`resposta_ao_dono`, a pergunta de esclarecimento
# dele): nunca um `next_question` que afirme aplicação. Com aviso de desfecho ou com falta apontada, needs_more_info.
module Autonomia::Agents::Builder::DesfechoDoAjuste
  # Desfechos da correção que só avisam o dono (nada a perguntar).
  AVISOS_DO_DESFECHO = { superado: :correcao_superada, apagado: :agente_apagado, agente_mudou: :agente_mudou }.freeze
  SEM_PENDENCIA = %i[manual superado apagado agente_mudou nao_conferido].freeze

  private

  # -> a conferência com `desfeito` ({ campos, tudo, ok }) quando havia item sem pedido do dono.
  def desfazer_o_que_nao_foi_pedido(dados, conferencia)
    sem_pedido = Array(conferencia['itens']).select { |item| item['pedido_pelo_dono'] == false }
    return conferencia if sem_pedido.empty?

    pedidos = Array(conferencia['itens']) - sem_pedido
    colunas, chaves = colunas_so_dos_nao_pedidos(sem_pedido, pedidos)
    ok = colunas.empty? && chaves.empty? ? true : desfazer!(dados, colunas, chaves)
    conferencia.merge('desfeito' => { 'campos' => regras_do_ajuste.campos(sem_pedido), 'tudo' => pedidos.empty?, 'ok' => ok })
  end

  def colunas_so_dos_nao_pedidos(sem_pedido, pedidos)
    colunas, chaves = colunas_e_chaves(regras_do_ajuste.campos(sem_pedido))
    colunas_pedidas, chaves_pedidas = colunas_e_chaves(regras_do_ajuste.campos(pedidos))
    [colunas - colunas_pedidas, chaves - chaves_pedidas]
  end

  # As colunas e as chaves do config destes campos.
  def colunas_e_chaves(campos)
    [campos.flat_map { |campo| regras_do_ajuste::COLUNAS_POR_CAMPO.fetch(campo, []) }.uniq.map(&:to_s),
     campos.filter_map { |campo| regras_do_ajuste::CHAVES_DA_CONFIG_POR_CAMPO[campo] }]
  end

  def desfazer!(dados, colunas, chaves)
    agent = @thread.agent
    ok = agent.desfazer_do_construtor!(dados['versao_antes_id'], colunas: colunas, chaves: chaves,
                                                                 esperado: dados['agente_updated_at'])
    agent.regravar_versao_do_construtor!(dados.dig('correcao', 'versao_id') || dados['versao_id'], dados['versao_antes_id']) if ok
    ok
  end

  # Fecha o turno aplicado. Ao dono vão, nesta ordem: a resposta à pergunta dele, o que entrou (quando parte foi
  # desfeita), o aviso do desfecho e a pendência.
  def fechar_ajuste!(token, dados, conferencia, desfecho)
    desfeito = conferencia['desfeito'].to_h
    resposta = dados.dig('correcao', 'resposta') || dados['resposta'].to_h
    return fechar_desfeito!(token, resposta, conferencia) if desfeito['tudo'] && desfeito['ok']

    mensagens, pendencia, aviso = conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    estado = estado_do_ajuste(resposta.merge('needs_more_info' => precisa?(pendencia, aviso, conferencia),
                                             'next_question' => mensagens.last.to_s))
             .merge(estado_aplicado(dados, conferencia, pendencia.presence || pendencia_mantida(resposta)))
    mensagens.each { |mensagem| persist_assistant_turn!(mensagem) } if @thread.mark_ready!(token, state: estado)
    log_do_ajuste(conferencia, desfecho)
  end

  # -> [mensagens ao dono, pendência, aviso]
  def conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    pendencia = pergunta_do_modelo(resposta) || pendencia_da_conferencia(conferencia, desfecho)
    aviso = aviso_do_desfecho(desfecho, dados, conferencia['desfeito'].to_h)
    [[resposta['resposta_ao_dono'].to_s.strip, o_que_entrou(conferencia), aviso, pendencia].compact_blank, pendencia, aviso]
  end

  def estado_aplicado(dados, conferencia, pendencia)
    { 'applied' => true, 'truncated_fields' => Array(dados['campos_truncados']) | @campos_truncados, 'so_pergunta' => false,
      'conferencia' => conferencia, 'pergunta_pendente' => pendencia.to_s, 'ajuste_em_curso' => nil }
  end

  # Com aviso de desfecho, pendência ou qualquer falta apontada, a conversa segue aberta.
  def precisa?(pendencia, aviso, conferencia)
    pendencia.present? || aviso.present? || conferencia['falta'] == true
  end

  # Tudo o que entrou não tinha sido pedido e foi desfeito: o turno é de sem mudança.
  def fechar_desfeito!(token, resposta, conferencia)
    sem_mudanca!(token, resposta, 'conferencia' => conferencia)
    log_do_ajuste(conferencia, :desfeito)
  end

  def o_que_entrou(conferencia)
    desfeito = conferencia['desfeito'].to_h
    return unless desfeito['ok'] && desfeito['tudo'] == false

    pedidos = Array(conferencia['itens']).reject { |item| item['pedido_pelo_dono'] == false }
    Autonomia::Agents::Builder::TextosDoAjuste.o_que_entrou(pedidos, idioma_do_ajuste)
  end

  def aviso_do_desfecho(desfecho, dados, desfeito)
    return texto_do_ajuste(:agente_mudou) if desfeito.present? && desfeito['ok'] == false
    if desfecho == :nao_conferido
      return texto_do_ajuste(:nao_conferido, pedidos: dados.dig('correcao', 'mudancas').to_a.pluck('pedido').uniq.join('; '))
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
      "desfeito=#{conferencia.dig('desfeito', 'campos').to_a.join(',')}"
    )
  end
end
