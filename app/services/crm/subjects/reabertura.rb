# #1638: o WhatsApp Híbrido (#1489) troca o aviso "mensagem não suportada" pelo texto real e grava
# `content_attributes['hybrid_recovered_at']` (contrato do #1637). A decisão que a IA tomou sozinha em cima do aviso é
# reaberta para ser tomada de novo com o texto real, na mesma linha: o índice único (conversa, mensagem) continua valendo.
#
# Só reabre o que foi da IA e ninguém tocou. Sugestão esperando a pessoa, escolha dela (aceita ou dispensada), reserva
# em curso e decisão vencida por uma mensagem mais nova ficam como estão. O card_id fica: o Applier dá o assunto novo
# ao MESMO card que a IA nomeou ou criou em cima do aviso, nunca a um segundo.
#
# Só uma vez: decisão gravada depois da recuperação já leu o texto real. A comparação é ao segundo, com tolerância (o
# horário da recuperação chega em ISO8601 sem fração): no mesmo segundo, reabre.
#
# Aceito (raro, e a próxima mensagem do cliente corrige): decisão reservada antes da recuperação e gravada depois dela
# pode ter lido o aviso e não reabre. Se o processo cair entre a reabertura e o fim, a linha fica pending, como a
# reserva de hoje; o erro dentro do job restaura o retrato (Identifier#desfazer_reserva).
module Crm::Subjects::Reabertura
  ESTADOS = %w[applied kept doubt no_content no_quota failed].freeze
  ZERADA = { state: 'pending', action: 'none', pipeline_id: nil, title: nil, confidence: nil, decided_by: nil,
             reason: nil, touched_card_ids: nil, jev_answer: nil, review_reason: nil }.freeze
  # O que a decisão era antes de reabrir: volta assim se der erro, e serve de comparação para não avisar à toa. A lista
  # de cards tocados (#1693) zera e não volta: a reaberta é de um assunto só, e a IA do CRM relê o card em foco.
  RETRATO = %w[state action card_id pipeline_id title confidence decided_by reason mode jev_answer review_reason updated_at].freeze

  # O retrato da decisão anterior, com a linha já reaberta (pending), ou nil quando não há o que reabrir. O update
  # condicional é a reserva: dois jobs da mesma mensagem não reabrem os dois.
  def self.reabrir(decisao, message, mode)
    recuperada_em = recuperada_em(message)
    return if recuperada_em.nil?

    retrato = decisao.attributes.slice(*RETRATO)
    reabertas = Crm::SubjectDecision.where(id: decisao.id, state: ESTADOS, updated_at: ...(recuperada_em + 1.second))
                                    .update_all(ZERADA.merge(mode: mode, updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    retrato if reabertas == 1
  end

  def self.recuperada_em(message)
    Time.iso8601(message.content_attributes.to_h['hybrid_recovered_at'].to_s).change(usec: 0)
  rescue ArgumentError
    nil
  end
  private_class_method :recuperada_em
end
