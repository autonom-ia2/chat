# #1428 (tema 6, parte 2) — o fim do turno de AJUSTE no piloto: o que não foi pedido volta a ser como era, e o que vai
# ao dono, a pendência e o state. Incluído no Builder junto com AjusteConferido e FechamentoDoAjuste.
#
# O QUE NÃO FOI PEDIDO: os itens são agrupados pelo `pedido` que o próprio Construtor escreveu (comparação do texto,
# sem ler linguagem). Um item com o mesmo `pedido` de um item pedido é destino secundário desse pedido (a tabela manda
# "no máximo 2 frases" para o tom E a instrução) e nunca é desfeito. Só quando TODOS os itens estão sem pedido o código
# desfaz sozinho, sob a trava, com o valor da versão de antes, e o turno fecha como não aplicado. Quando só parte está
# sem pedido, tudo fica aplicado e o dono é informado pelo cartão do resultado na tela (parte 3, uma linha à parte,
# sem bolha na conversa), sem pergunta: o desfazer exato é o botão Desfazer.
#
# Ao dono só vão textos do código e dos campos próprios do Construtor (`resposta_ao_dono`, a pergunta de esclarecimento
# dele): nunca um `next_question` que afirme aplicação. Com aviso de desfecho ou com falta apontada, needs_more_info.
module Autonomia::Agents::Builder::DesfechoDoAjuste
  # Desfechos da correção que só avisam o dono (nada a perguntar).
  AVISOS_DO_DESFECHO = { superado: :correcao_superada, apagado: :agente_apagado, agente_mudou: :agente_mudou }.freeze
  SEM_PENDENCIA = %i[manual superado apagado agente_mudou nao_conferido].freeze
  # Pela tabela de destino: o campo da chave acompanha estes campos principais ("no maximo 2 frases" vai para o tom E
  # a instrução; um limite, para guardrails E a instrução; a passagem, para handoff_rule E a instrução).
  SECUNDARIO_DE = { 'instruction' => %w[tone guardrails handoff_rule] }.freeze

  # Sem pedido do dono, sem o mesmo `pedido` de um item pedido e sem ser o destino secundário, pela tabela, de um item
  # pedido (a instrução acompanha o tom, os limites e a passagem). Na dúvida, conta como pedido: não se pergunta.
  # Público: o resultado na tela (ResultadoDoAjuste, parte 3) separa os itens pela mesma regra.
  def self.sem_pedido(itens)
    pedidos = itens.reject { |item| item['pedido_pelo_dono'] == false }
    textos = pedidos.pluck('pedido')
    campos = pedidos.pluck('campo')
    itens.select do |item|
      item['pedido_pelo_dono'] == false && textos.exclude?(item['pedido']) &&
        !SECUNDARIO_DE.fetch(item['campo'], []).intersect?(campos)
    end
  end

  private

  # -> a conferência com `sem_pedido` (os itens que o dono não pediu, quando é só parte) ou `desfeito`
  # ({ campos, ok }, quando era tudo e o código desfez).
  def desfazer_o_que_nao_foi_pedido(token, dados, conferencia)
    itens = Array(conferencia['itens'])
    sem_pedido = itens_sem_pedido(itens)
    return conferencia if sem_pedido.empty?
    return conferencia.merge('sem_pedido' => so_o_que_mudou(dados, sem_pedido).presence).compact if sem_pedido.size < itens.size

    conferencia.merge('desfeito' => { 'campos' => regras_do_ajuste.campos(itens), 'ok' => desfazer!(token, dados, itens) })
  end

  # Só cita ao dono o campo não pedido que mudou de fato (o Construtor pode listar um campo e devolvê-lo igual).
  def so_o_que_mudou(dados, itens)
    antes = retrato_de_antes(dados)
    depois = regras_do_ajuste.retrato(@thread.agent)
    itens.reject { |item| antes[item['campo']] == depois[item['campo']] }
  end

  def itens_sem_pedido(itens)
    Autonomia::Agents::Builder::DesfechoDoAjuste.sem_pedido(itens)
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

    conversa = conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    mensagens = conversa.first
    estado = estado_do_fechamento(dados, conferencia, resposta, conversa)
    if @thread.mark_ready!(token, state: estado)
      mensagens.each { |mensagem| persist_assistant_turn!(mensagem) }
      # #1428 (parte 3, entrega B): o cartão sai agora; a prova chega segundos depois, pelo job.
      Autonomia::Agents::ProvaDoAjusteJob.perform_later(@thread.id, estado.dig('prova', 'versao_id')) if estado['prova']
    end
    log_do_ajuste(conferencia, desfecho)
  end

  # O state do turno aplicado, a partir da conversa do fechamento.
  def estado_do_fechamento(dados, conferencia, resposta, conversa)
    mensagens, pendencia, aviso, opcoes, na_tela = conversa
    estado_do_ajuste(resposta.merge('needs_more_info' => precisa?(pendencia.first, aviso, conferencia),
                                    'next_question' => mensagens.last.to_s))
      .merge(estado_aplicado(dados, conferencia, resposta, pendencia))
      .merge('opcoes_de_resposta' => opcoes, 'pergunta_na_tela' => pergunta_na_tela(pendencia.first, na_tela))
  end

  # -> [mensagens ao dono, [pendência, origem], aviso, opções, pergunta na tela]. A pergunta que o código abre sobre o
  # turno (:codigo) zera a contagem da pendência; a do modelo (:modelo) conta como laço. O que o dono não pediu não vira
  # bolha: o cartão do resultado na tela mostra (parte 3). As opções são as de quem fez a pergunta, que é sempre a
  # última mensagem.
  def conversa_do_fechamento(dados, conferencia, desfecho, resposta)
    do_modelo = pergunta_do_modelo(resposta)
    texto, opcoes, na_tela = do_modelo ? [do_modelo, opcoes_do_modelo(resposta)] : pergunta_da_conferencia(conferencia, desfecho)
    origem = origem_da_pendencia(texto, do_modelo)
    aviso = aviso_do_desfecho(desfecho, dados, conferencia)
    [[resposta['resposta_ao_dono'].to_s.strip, aviso, texto].compact_blank, [texto, origem], aviso, opcoes, na_tela]
  end

  # #1850 — a pergunta inteira fica na conversa e na pendência; a tela, enquanto o cartão ⚠ do turno está lá, mostra a
  # versão sem o que o cartão já mostra (ResultadoDoAjuste#to_h, só enquanto `inteira` é a pergunta aberta). nil quando
  # as duas são iguais.
  def pergunta_na_tela(inteira, curta)
    { 'inteira' => inteira, 'curta' => curta } if inteira.present? && curta.present? && curta != inteira
  end

  # A referência (versão de antes e campos) do que o dono não pediu, para o turno seguinte: "tira isso" volta ao valor
  # de antes, que o Construtor recebe como contexto interno. Nunca o texto cru.
  def nao_pedido_anterior(dados, conferencia)
    itens = Array(conferencia['sem_pedido'])
    { 'versao_antes_id' => dados['versao_antes_id'], 'campos' => regras_do_ajuste.campos(itens) } if itens.any?
  end

  def origem_da_pendencia(texto, do_modelo)
    return :mantida if texto.nil?

    do_modelo ? :modelo : :codigo
  end

  # O turno aplicado conta como laço para a pendência que segue aberta. `parcial`: falta apontada ou pergunta do
  # modelo (a tela diz "parte entrou"); o "também mudei" sozinho não é parcial.
  def estado_aplicado(dados, conferencia, resposta, pendencia)
    texto, origem = pendencia
    { 'applied' => true, 'truncated_fields' => Array(dados['campos_truncados']) | @campos_truncados, 'so_pergunta' => false,
      'conferencia' => conferencia, 'ajuste_em_curso' => nil, 'nao_pedido_anterior' => nao_pedido_anterior(dados, conferencia),
      'parcial' => conferencia['falta'] == true || pergunta_do_modelo(resposta).present?,
      'ultimo_ajuste' => ultimo_ajuste(dados, conferencia),
      'prova' => Autonomia::Agents::ProvaDoAjuste.pendente(@thread.agent, dados) }
      .merge(pendencia_no_estado(texto || pendencia_mantida(resposta), resposta, origem: origem, laco: true))
  end

  # #1428 (parte 3) — o que o Desfazer da tela precisa: a versão de antes, a da aplicação (a da correção, se houve) e a
  # conferência do turno (a faixa "Última mudança" lê dela o que entrou e o que não foi pedido, mesmo depois de uma
  # pergunta). A API não expõe esta chave; o que vai à tela passa pelo ResultadoDoAjuste.
  def ultimo_ajuste(dados, conferencia)
    { 'versao_antes_id' => dados['versao_antes_id'], 'versao_id' => dados.dig('correcao', 'versao_id') || dados['versao_id'],
      'conferencia' => conferencia }
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

  # -> [pergunta, opções, pergunta na tela] que o código abre sobre o turno. A do que faltou leva as opções da correção
  # só quando a explicação dela está na pergunta; a do conflito, os dois botões fixos. O caminho diz qual é, nunca o texto.
  def pergunta_da_conferencia(conferencia, desfecho)
    return [nil, []] if SEM_PENDENCIA.include?(desfecho)
    return pergunta_do_que_faltou(conferencia) if conferencia['falta']
    return [nil, []] unless conferencia['conflito']

    textos = Autonomia::Agents::Builder::TextosDoAjuste
    [textos.pergunta_do_conflito(Array(conferencia['itens']), idioma_do_ajuste), textos.opcoes_do_conflito(idioma_do_ajuste)]
  end

  def pergunta_do_que_faltou(conferencia)
    textos = Autonomia::Agents::Builder::TextosDoAjuste
    explicacao = @explicacao_da_correcao
    [textos.pergunta_do_que_faltou(conferencia, idioma_do_ajuste, explicacao: explicacao),
     explicacao ? @opcoes_da_correcao : [], textos.pergunta_na_tela(conferencia, idioma_do_ajuste, explicacao: explicacao)]
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
