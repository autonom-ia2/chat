# #3101: Autonomia::MelhorHorario::Aprender todo dia de madrugada (config/schedule.yml).
class Autonomia::MelhorHorario::AprenderJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Autonomia::MelhorHorario::Aprender.rodar
  end
end
