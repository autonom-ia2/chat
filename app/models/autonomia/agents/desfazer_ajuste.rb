# #1428 (tema 6, parte 3) — o DESFAZER do último ajuste do "Mudar conversando". SÓ NO PILOTO (Fase 2 dos Agentes).
#
# Volta o agente, exato, ao estado da versão de antes do ajuste (os campos versionados, as chaves do config que o
# Construtor escreve e a instrução) e grava a versão 'rollback' com `voltou_para` e `desfez_ajuste`. A versão aplicada
# continua na lista, marcada `desfeita` (decisão do Rodrigo, 18/10): as duas ficam visíveis em Versões. O resto do
# agente (ligado ou não, materiais, conhecimento, demais chaves do config) fica como está.
#
# Vale até a próxima MUDANÇA de verdade no agente (decisão do Rodrigo, 18/10): enquanto os campos versionados forem os
# que a aplicação gravou na versão dela. Ligar ou desligar, materiais e uma pergunta ao Construtor não tiram o Desfazer;
# mudar o comportamento pela gaveta, voltar a uma versão ou outro ajuste tiram. Sob a trava, a mesma regra decide; se
# não vale mais, AjusteMudou (409) e o caminho é Versões. Pedir de novo depois de desfeito responde igual, sem versão nova
# (a volta por Versões apaga o ajuste guardado: aí o pedido repetido é 409).
#
# JOB EM VOO (revisão adversarial F3): o Desfazer toma o token de toda conversa do agente gerando agora, de qualquer
# idade, sob a mesma ordem de travas da escrita do Construtor (a conversa, depois o agente). A escrita atrasada falha na
# guarda do token, e a conversa superada mostra ao dono que o pedido foi cancelado.
#
# Não reusa restore_instruction! (passa um agente manual a guiado) nem desfazer_do_construtor! (exige a geração em
# andamento).
module Autonomia::Agents::DesfazerAjuste
  extend ActiveSupport::Concern

  class AjusteMudou < StandardError; end

  # O que a volta não devolve fica fora da comparação; as chaves do config que a versão guarda.
  FORA_DA_COMPARACAO = Autonomia::Agents::AgentVersioning::SO_PARA_COMPARAR
  CHAVES_VERSIONADAS_DO_CONFIG = Autonomia::Agents::AgentVersioning::CHAVES_DA_CONFIG

  SUPERADA = 'superada_pelo_desfazer'.freeze

  # A REGRA ÚNICA do Desfazer: a conversa mais nova do agente com um ajuste guardado (`ultimo_ajuste`), ainda não
  # desfeito, e o agente ainda com os campos que a aplicação gravou. nil sem ela. A tela usa (o cartão da conversa e a
  # faixa "Última mudança", mesmo depois de recarregar) e o desfazer confere de novo sob as travas.
  def conversa_desfazivel
    return unless versao_completa? && guided?

    thread = build_threads.where(account_id: account_id).where("jsonb_typeof(state->'ultimo_ajuste') = 'object'")
                          .order(id: :desc).first
    thread if thread && ajuste_aberto?(thread.state['ultimo_ajuste'])
  end

  def desfazer_ajuste!(thread:, created_by: nil)
    recusar_se_instrucao_mantida!
    recusar_se_modo_manual!
    raise ActiveRecord::RecordNotFound unless versao_completa? && thread.autonomia_agent_id == id

    # Sob as travas, tudo relido: o agente pode ter passado a manual ou mudado depois que a tela mostrou o botão. As
    # conversas em voo travam antes do agente, na mesma ordem da escrita do Construtor (sem deadlock).
    transaction { desfazer_sob_as_travas!(thread, created_by) }
  end

  private

  def desfazer_sob_as_travas!(thread, autor)
    # Todas as conversas do agente (inclusive a deste Desfazer, que recebe a marca), não só as em voo: uma conversa parada
    # que começasse a gerar no meio pegaria a trava dela antes de nós e esperaria o agente.
    em_voo = travar_conversas!.select(&:processing?)
    lock!
    ultimo = thread.reload.state.to_h['ultimo_ajuste'].to_h
    return true if ultimo['desfeito'] == true
    raise AjusteMudou unless conversa_desfazivel&.id == thread.id

    em_voo.each { |conversa| conversa.mark_failed!(conversa.build_token, SUPERADA) }
    voltar_ao_antes_do_ajuste!(thread, ultimo, autor)
  end

  # Não desfeito, e os campos versionados do agente são os que a aplicação gravou na versão dela.
  def ajuste_aberto?(ultimo)
    return false if ultimo['desfeito'] == true || ultimo['versao_antes_id'].blank?

    aplicada = instruction_versions.find_by(id: ultimo['versao_id'])
    aplicada.present? && aplicada.instruction_hash == hash_da_instrucao &&
      aplicada.metadata.to_h['agente'].to_h.except(*FORA_DA_COMPARACAO) == retrato_da_versao.as_json.except(*FORA_DA_COMPARACAO)
  end

  def voltar_ao_antes_do_ajuste!(thread, ultimo, autor)
    antes = instruction_versions.find_by(id: ultimo['versao_antes_id']) || raise(AjusteMudou)
    update_columns(atributos_de_antes(antes).merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    gravar_versao!('rollback', autor&.id, extra: { 'voltou_para' => antes.id, 'desfez_ajuste' => ultimo['versao_id'] }.compact)
    aplicada = instruction_versions.find_by(id: ultimo['versao_id'])
    aplicada&.update!(metadata: aplicada.metadata.to_h.merge('desfeita' => true))
    # Só a marca (e o "tira isso", que não vale mais), sem regravar o state inteiro.
    marca = "state = jsonb_set(state - 'nao_pedido_anterior', '{ultimo_ajuste,desfeito}', 'true'::jsonb)"
    Autonomia::Agents::BuildThread.where(id: thread.id).update_all(marca) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  # A ORDEM DAS TRAVAS, a mesma da escrita do Construtor: as conversas do agente primeiro (só as da conta, por id),
  # depois o agente. O Desfazer e a volta por Versões seguem esta ordem; ninguém trava o agente e depois a conversa.
  def travar_conversas!
    build_threads.where(account_id: account_id).order(:id).lock.to_a
  end

  # A volta por Versões encerra o Desfazer pela conversa: o ajuste guardado e o "tira isso" saem das conversas do agente
  # (um Desfazer repetido depois dela é 409, nunca um "desfeito" com o agente em outro estado), e a versão desfeita
  # a que se voltou perde a marca `desfeita` (ela está de novo no agente).
  def depois_de_voltar_por_versoes!(version)
    build_threads.where("state ?| array['ultimo_ajuste', 'nao_pedido_anterior']")
                 .update_all("state = state - 'ultimo_ajuste' - 'nao_pedido_anterior'") # rubocop:disable Rails/SkipsModelValidations
    return unless version.metadata.to_h.key?('desfeita')

    version.update!(metadata: version.metadata.except('desfeita'))
  end

  # Os campos guardados na versão de antes. A chave do config que não existia antes (o retrato guarda nil) sai, em vez
  # de ficar gravada com nil.
  def atributos_de_antes(antes)
    atributos = atributos_guardados(antes)
    return atributos unless atributos.key?('config')

    atributos.merge('config' => atributos['config'].reject { |chave, valor| CHAVES_VERSIONADAS_DO_CONFIG.include?(chave) && valor.nil? })
  end
end
