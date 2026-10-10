# Corpo de "Depois da reunião" (#1193, J4-A7) no PATCH da página: `post_meeting: { mode, stage_id }` vira as colunas
# do perfil. Só o que veio muda; etapa vazia desliga a oferta. A etapa é conferida pelo modelo (funil ativo desta
# conta); id que não é número vira 0, que nenhuma etapa tem, para a validação recusar em vez de a coluna inteira
# engolir o texto como vazio.
class Crm::BookingV2::PostMeetingParams
  def self.attributes(body)
    raw = body.permit(post_meeting: [:mode, :stage_id]).to_h['post_meeting']
    return {} unless raw.is_a?(Hash)

    attributes = {}
    attributes[:post_meeting_mode] = raw['mode'] if raw.key?('mode')
    attributes[:post_meeting_stage_id] = stage_id(raw['stage_id']) if raw.key?('stage_id')
    attributes
  end

  def self.stage_id(raw)
    return if raw.blank?

    Integer(raw.to_s, exception: false) || 0
  end

  private_class_method :stage_id
end
