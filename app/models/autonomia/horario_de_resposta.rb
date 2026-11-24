# A hora em que um cliente costuma escrever (#3101, melhor horário). Quem grava é Autonomia::MelhorHorario::Aprender, a
# partir das mensagens dele nos últimos 180 dias, no fuso dele. `hora` fica nula enquanto não há o mínimo de mensagens.
class Autonomia::HorarioDeResposta < ApplicationRecord
  self.table_name = 'horarios_de_resposta'

  belongs_to :account
  belongs_to :contact

  # A hora dele, ou, se ela cai fora do horário de envio da conta (`horario` de Autonomia::RitmoDeEnvio::Config), a
  # hora permitida em que ele mais escreveu.
  def hora_permitida(horario)
    return hora if hora.nil? || horario.nil?

    permitidas = (horario['inicio']...horario['fim'])
    return hora if permitidas.cover?(hora)

    permitidas.max_by { |vez| por_hora[vez].to_i }
  end
end
