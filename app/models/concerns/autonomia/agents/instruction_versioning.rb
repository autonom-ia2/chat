module Autonomia::Agents::InstructionVersioning
  def current_instruction_version
    return if instruction.blank?

    effective_origin = manual? ? 'manual' : 'guided'
    instruction_versions.order(created_at: :desc, id: :desc).find do |version|
      version.instruction == instruction && version.current_for?(effective_origin)
    end
  end

  def latest_guided_instruction_version
    instruction_versions.order(created_at: :desc, id: :desc).find(&:guided_origin?)
  end

  def guided_version?
    latest_guided_instruction_version.present?
  end

  # G2 — ROLLBACK ATÔMICO: restaura `instruction` para o texto de `version` e grava um novo
  # snapshot na mesma transação. A versão precisa pertencer a este agente e ter origem comprovada.
  def restore_instruction!(version, created_by: nil)
    recusar_se_instrucao_mantida!
    return false unless restorable_version?(version)

    with_lock { restore_instruction_state!(version, created_by) }
    true
  end

  def record_instruction_version!(reason:, created_by: nil, force: false, origin: nil)
    current = instruction.to_s
    return if current.blank?

    digest = Digest::SHA256.hexdigest(current)
    last = instruction_versions.order(created_at: :desc, id: :desc).first
    return if !force && last&.instruction_hash == digest

    write_instruction_version!(current, digest, reason, created_by, origin: origin, scaffold: scaffold)
  end

  private

  def restorable_version?(version)
    return false if version.blank? || version.autonomia_agent_id != id
    return true if version.guided_origin? || version.manual_origin?

    raise ::Autonomia::Agents::Errors::UnrestorableVersion
  end

  def restore_instruction_state!(version, created_by)
    guided = version.guided_origin?
    restored_scaffold = restored_scaffold_for(version, guided)
    instruction_changed = instruction_changed?(version, guided, restored_scaffold)
    persist_restored_instruction!(version, guided, restored_scaffold)
    invalidate_before_live_test('person') if instruction_changed
    write_instruction_version!(
      version.instruction, Digest::SHA256.hexdigest(version.instruction), 'rollback', created_by,
      origin: guided ? 'guided' : 'manual', scaffold: restored_scaffold
    )
  end

  def restored_scaffold_for(version, guided)
    version.scaffold_snapshot.presence || (guided ? scaffold : ::Autonomia::Agents::Agent::MANUAL_SCAFFOLD)
  end

  def instruction_changed?(version, guided, restored_scaffold)
    instruction != version.instruction || mode != (guided ? 'guided' : 'manual') || scaffold != restored_scaffold
  end

  def persist_restored_instruction!(version, guided, restored_scaffold)
    # Rollback is already inside the agent lock and must write the live state without callbacks
    # between the restored columns and its new history snapshot.
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(
      instruction: version.instruction,
      mode: self.class.modes.fetch(guided ? 'guided' : 'manual'),
      scaffold: restored_scaffold,
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def write_instruction_version!(text, digest, reason, created_by, options = {})
    origin = options[:origin]
    scaffold = options[:scaffold]
    metadata = { 'agent_name' => name.to_s }
    metadata['origin'] = origin.presence || inferred_instruction_origin(reason)
    metadata['scaffold'] = scaffold if scaffold.present?

    instruction_versions.create!(
      account_id: account_id, instruction: text, instruction_hash: digest,
      reason: reason, created_by: created_by,
      metadata: metadata
    )
  end

  def inferred_instruction_origin(reason)
    return 'guided' if %w[builder before_manual kb_refresh].include?(reason.to_s)

    'manual'
  end
end
