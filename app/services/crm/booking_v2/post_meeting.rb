# Depois de "Aconteceu" (#1193, J4-A7): oferece mover o card para a etapa que o admin escolheu na página de
# agendamento (`post_meeting`). Em `auto` move sozinho (`Crm::Cards::Mover`, que registra a atividade `move` e roda
# as automações da etapa); em `ask` só devolve a pergunta para a tela ("Mover" / "Agora não"), e o "Mover" usa a
# rota de mover card que já existe.
#
# Nada a oferecer (nil): reunião sem página nova, página sem etapa (ou com funil arquivado), card que não está aberto,
# que já está nessa etapa ou que está num funil fora do fluxo da página. Uma vez por reunião: quem chama
# (`RecordOutcomeService`) garante, sob trava, que só o primeiro "Aconteceu" chega aqui.
class Crm::BookingV2::PostMeeting
  def initialize(meeting:, actor:)
    @meeting = meeting
    @actor = actor
  end

  # { mode: 'ask'|'auto', moved: true|false, stage: { id, name, pipeline_id } } ou nil.
  def perform
    stage = target_stage
    return if stage.blank?

    moved = profile.post_meeting_mode == 'auto' && move!(stage)
    { mode: profile.post_meeting_mode, moved: moved, stage: { id: stage.id, name: stage.name, pipeline_id: stage.pipeline_id } }
  end

  private

  attr_reader :meeting, :actor

  def profile
    @profile ||= Crm::BookingV2::Notices::Scheduler.profile_for(meeting)
  end

  def target_stage
    return unless meeting.outcome_held? && profile.present?

    stage = profile.post_meeting_target
    card = meeting.card
    stage if stage.present? && card.open? && card.stage_id != stage.id && same_flow?(card, stage)
  end

  # Só o card que está no fluxo da página: no funil para onde a página manda quem marca ou no funil da etapa
  # escolhida. Card de outro funil (o botão Agendar vale para qualquer card) não é levado para lá por engano.
  def same_flow?(card, stage)
    [profile.default_pipeline_id, stage.pipeline_id].compact.include?(card.pipeline_id)
  end

  def move!(stage)
    card = Crm::Cards::Mover.new(card: meeting.card, actor: actor, target_stage: stage).perform
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED)
    true
  end
end
