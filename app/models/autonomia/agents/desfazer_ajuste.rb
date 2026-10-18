# #1428 (tema 6, parte 3) — o DESFAZER do último ajuste do "Mudar conversando". SÓ NO PILOTO (Fase 2 dos Agentes).
#
# Volta o agente, exato, ao estado da versão de antes do ajuste (os campos versionados, as chaves do config que o
# Construtor escreve e a instrução) e grava a versão 'rollback' com `voltou_para` e `desfez_ajuste`. A versão aplicada
# continua na lista, marcada `desfeita` (decisão do Rodrigo, 18/10): as duas ficam visíveis em Versões.
#
# Vale até a próxima mudança no agente. Sob a trava do agente: ele tem de estar como a escrita do Construtor o deixou
# (o updated_at guardado no fechamento, `ultimo_ajuste`), e a conversa tem de ser a mais nova do agente e estar parada.
# Senão, AjusteMudou (409) e o caminho é Versões. Pedir de novo depois de desfeito responde igual, sem versão nova.
#
# Não reusa restore_instruction! (passa um agente manual a guiado e não confere o updated_at) nem
# desfazer_do_construtor! (exige a geração em andamento).
module Autonomia::Agents::DesfazerAjuste
  extend ActiveSupport::Concern

  class AjusteMudou < StandardError; end

  # O ajuste desta conversa ainda pode ser desfeito aqui? (a tela mostra o botão; o desfazer confere de novo sob a trava)
  def ajuste_desfazivel?(thread)
    ultimo = thread.state.to_h['ultimo_ajuste'].to_h
    return false unless guided? && ultimo['desfeito'] != true

    thread.ready? && ultimo['versao_antes_id'].present? && updated_at.iso8601(6) == ultimo['agente_updated_at'] &&
      !build_threads.where(account_id: account_id).exists?(['id > ?', thread.id])
  end

  def desfazer_ajuste!(thread:, created_by: nil)
    recusar_se_instrucao_mantida!
    recusar_se_modo_manual!
    raise ActiveRecord::RecordNotFound unless versao_completa? && thread.autonomia_agent_id == id

    # Sob a trava, tudo relido: o agente pode ter passado a manual ou mudado depois que a tela mostrou o botão.
    with_lock do
      ultimo = thread.reload.state.to_h['ultimo_ajuste'].to_h
      next true if ultimo['desfeito'] == true
      raise AjusteMudou unless ajuste_desfazivel?(thread)

      voltar_ao_antes_do_ajuste!(thread, ultimo, created_by)
    end
  end

  private

  def voltar_ao_antes_do_ajuste!(thread, ultimo, autor)
    antes = instruction_versions.find_by(id: ultimo['versao_antes_id']) || raise(AjusteMudou)
    update_columns(atributos_guardados(antes).merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    gravar_versao!('rollback', autor&.id, extra: { 'voltou_para' => antes.id, 'desfez_ajuste' => ultimo['versao_id'] }.compact)
    aplicada = instruction_versions.find_by(id: ultimo['versao_id'])
    aplicada&.update!(metadata: aplicada.metadata.to_h.merge('desfeita' => true))
    # Só a marca, sem regravar o state inteiro (uma mensagem nova pode estar entrando na conversa).
    marca = "state = jsonb_set(state, '{ultimo_ajuste,desfeito}', 'true'::jsonb)"
    Autonomia::Agents::BuildThread.where(id: thread.id).update_all(marca) # rubocop:disable Rails/SkipsModelValidations
    true
  end
end
