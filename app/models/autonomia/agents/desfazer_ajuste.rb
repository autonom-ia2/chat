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
# não vale mais, AjusteMudou (409) e o caminho é Versões. Pedir de novo depois de desfeito responde igual, sem versão nova.
#
# Não reusa restore_instruction! (passa um agente manual a guiado) nem desfazer_do_construtor! (exige a geração em
# andamento).
module Autonomia::Agents::DesfazerAjuste
  extend ActiveSupport::Concern

  class AjusteMudou < StandardError; end

  # O que a volta não devolve fica fora da comparação; as chaves do config que a versão guarda.
  FORA_DA_COMPARACAO = Autonomia::Agents::AgentVersioning::SO_PARA_COMPARAR
  CHAVES_VERSIONADAS_DO_CONFIG = Autonomia::Agents::AgentVersioning::CHAVES_DA_CONFIG

  # A REGRA ÚNICA do Desfazer: a conversa mais nova do agente com um ajuste guardado (`ultimo_ajuste`), ainda não
  # desfeito, sem nenhuma conversa do agente gerando agora, e o agente ainda com os campos que a aplicação gravou. nil
  # sem ela. A tela usa (o cartão da conversa e a faixa "Última mudança", mesmo depois de recarregar) e o desfazer
  # confere de novo sob a trava.
  def conversa_desfazivel
    return unless versao_completa? && guided?
    return if build_threads.processing.exists?(['updated_at >= ?', Autonomia::Agents::BuildThread::STALE_PROCESSING_AFTER.ago])

    thread = build_threads.where(account_id: account_id).where("jsonb_typeof(state->'ultimo_ajuste') = 'object'")
                          .order(id: :desc).first
    thread if thread && ajuste_aberto?(thread.state['ultimo_ajuste'])
  end

  def desfazer_ajuste!(thread:, created_by: nil)
    recusar_se_instrucao_mantida!
    recusar_se_modo_manual!
    raise ActiveRecord::RecordNotFound unless versao_completa? && thread.autonomia_agent_id == id

    # Sob a trava, tudo relido: o agente pode ter passado a manual ou mudado depois que a tela mostrou o botão.
    with_lock do
      ultimo = thread.reload.state.to_h['ultimo_ajuste'].to_h
      next true if ultimo['desfeito'] == true
      raise AjusteMudou unless conversa_desfazivel&.id == thread.id

      voltar_ao_antes_do_ajuste!(thread, ultimo, created_by)
    end
  end

  private

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
    # Só a marca, sem regravar o state inteiro (uma mensagem nova pode estar entrando na conversa).
    marca = "state = jsonb_set(state, '{ultimo_ajuste,desfeito}', 'true'::jsonb)"
    Autonomia::Agents::BuildThread.where(id: thread.id).update_all(marca) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  # Voltar (por Versões) a uma versão desfeita a põe de novo no agente: a marca `desfeita` não fica mentindo.
  def tirar_marca_desfeita!(version)
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
