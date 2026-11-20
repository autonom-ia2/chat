# #3063 (item 2): Autonomia::RitmoDeEnvio::Varredura a cada 5 minutos (config/schedule.yml). Destinatário adiado sai até
# 5 minutos depois da hora em que pode.
class Autonomia::RitmoDeEnvio::VarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Autonomia::RitmoDeEnvio::Varredura.rodar
  end
end
