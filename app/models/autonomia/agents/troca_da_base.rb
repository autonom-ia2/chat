# F3 do tema 8 (#1429): "Atualizar com a nova base" e o Desfazer dela. SÓ NA FASE 2 (a versão do agente inteiro).
#
# A troca grava SÓ `config['base']` (a marca do segmento: segmento, versao, texto). Instrução, tom, material e
# ferramentas ficam como estão. Fica no histórico de versões que já existe (#1428): antes da troca, se o estado atual
# ainda não está na última versão da lista, ele é guardado como 'base' (o estado de antes); depois, a versão
# 'base_de_seguros' ("Base de seguros atualizada"), com `versao_antes_id`.
#
# O Desfazer vale até a próxima MUDANÇA de verdade no agente, a mesma regra do Desfazer do ajuste conversado: enquanto a
# versão da troca é a última da lista, não foi desfeita e os campos versionados do agente são os que ela gravou. Ligar ou
# desligar não tiram o Desfazer; editar o comportamento, voltar a uma versão ou um ajuste tiram. Desfazer devolve só a
# base de antes (o resto é, por essa regra, igual ao de antes) e grava a versão 'rollback' com `desfez_base`.
#
# As travas seguem a ordem da escrita do Construtor: as conversas do agente, depois o agente (`travar_conversas!`).
module Autonomia::Agents::TrocaDaBase
  extend ActiveSupport::Concern

  MOTIVO = 'base_de_seguros'.freeze

  # Sem a Fase 2 ou sem instrução não há versão onde guardar a troca (e, portanto, Desfazer).
  class TrocaIndisponivel < StandardError; end
  # O agente mudou depois da troca (ou nunca houve troca): o caminho é Versões.
  class BaseMudou < StandardError; end

  # Pode trocar: Fase 2 ligada e uma instrução para a versão guardar.
  def troca_da_base_disponivel?
    versao_completa? && instruction.present?
  end

  # -> true quando trocou, false quando a base já era essa.
  def trocar_base!(marca, created_by: nil)
    recusar_se_instrucao_mantida!
    raise TrocaIndisponivel unless troca_da_base_disponivel?

    transaction do
      travar_conversas!
      lock!
      next false if config.to_h['base'] == marca

      gravar_versao!('base', nil) unless estado_atual_guardado?
      antes = ultima_versao(instruction_versions.na_lista)
      update_columns(config: config.to_h.merge('base' => marca), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      gravar_versao!(MOTIVO, created_by&.id, extra: { 'versao_antes_id' => antes&.id })
      true
    end
  end

  # A versão da troca de base que ainda pode ser desfeita, ou nil.
  def base_desfazivel
    return unless versao_completa?

    ultima = ultima_versao(instruction_versions.na_lista)
    ultima if ultima&.reason == MOTIVO && troca_aberta?(ultima)
  end

  # A base guardada na versão de antes da troca (nil quando o agente não tinha marca). Só faz sentido com base_desfazivel.
  def base_antes_da_troca(aplicada)
    antes = instruction_versions.find_by(id: aplicada.metadata.to_h['versao_antes_id'])
    antes.metadata.to_h.dig('agente', 'config').to_h['base'] if antes
  end

  def desfazer_troca_da_base!(created_by: nil)
    recusar_se_instrucao_mantida!

    transaction do
      travar_conversas!
      lock!
      aplicada = base_desfazivel || raise(BaseMudou)
      antes = instruction_versions.find_by(id: aplicada.metadata.to_h['versao_antes_id']) || raise(BaseMudou)
      voltar_a_base_de!(antes)
      gravar_versao!('rollback', created_by&.id, extra: { 'voltou_para' => antes.id, 'desfez_base' => aplicada.id })
      aplicada.update!(metadata: aplicada.metadata.to_h.merge('desfeita' => true))
      true
    end
  end

  private

  def troca_aberta?(aplicada)
    fora = Autonomia::Agents::AgentVersioning::SO_PARA_COMPARAR
    aplicada.metadata.to_h['desfeita'] != true && aplicada.instruction_hash == hash_da_instrucao &&
      aplicada.metadata.to_h['agente'].to_h.except(*fora) == retrato_da_versao.as_json.except(*fora)
  end

  # A chave 'base' como estava na versão de antes: ausente lá (o agente nasceu sem marca), ausente aqui.
  def voltar_a_base_de!(antes)
    config_antes = antes.metadata.to_h.dig('agente', 'config').to_h
    base = config_antes['base']
    raise BaseMudou unless Autonomia::Agents::RetratoDaVersao.base_valida?(base)

    novo = config_antes.key?('base') ? config.to_h.merge('base' => base) : config.to_h.except('base')
    update_columns(config: novo, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
