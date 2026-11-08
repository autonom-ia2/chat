# card.antes_da_reuniao (#2709): o lembrete antes da reunião. O momento do lembrete é o início menos `antes` ou, se a
# reunião foi marcada depois disso (em cima da hora), o instante em que foi marcada. Não é o `updated_at`: a
# confirmação do cliente e o aviso da página gravam na reunião, e o lembrete de antes de ligar dispararia no primeiro
# toque. Remarcada em cima da hora, lembra se o novo momento cair na janela; mais de 1 dia antes de agora, não. A cada rodada entram as reuniões
# agendadas e ainda por vir da conta cujo momento caiu na janela (de 1 dia para trás, nunca antes de ligar); com
# `pagina_id`, só as marcadas por aquela página de agendamento. O alvo é o card da reunião.
#
# - Remarcada: o início muda, e a marca também (Gatilhos.marca_do_lembrete): lembra no horário novo. O lembrete do
#   horário antigo, se ainda não chegou, nunca chega.
# - Cancelada (ou já começou): sai da busca, não lembra.
# - Marcada com menos tempo do que `antes`: lembra na rodada seguinte, uma vez.
# - Ligar não age no passado: o lembrete cujo momento é anterior a ligar (ou a salvar a versão ligada) não roda.
# - O card da reunião aberto ou que deu certo, como na varredura de data (Tempo::Data): o perdido e o arquivado sem
#   desfecho não recebem lembrete.
class Autonomia::Automacao::Tempo::AntesDaReuniao
  MOMENTO = 'GREATEST(crm_meetings.starts_at - make_interval(secs => ?), crm_meetings.created_at) BETWEEN ? AND ?'.freeze

  def initialize(definicao:, gatilho:, agora:)
    @definicao = definicao
    @gatilho = gatilho
    @agora = agora
  end

  def cada
    escopo.includes(:card).find_each do |reuniao|
      yield reuniao.card, ::Autonomia::Automacao::Gatilhos.marca_do_lembrete(reuniao)
    end
  end

  def escopo
    antes = ::Autonomia::Automacao::Duracao.de(@gatilho['antes'])
    desde = [@agora - ::Autonomia::Automacao::Tempo::JANELA, ::Autonomia::Automacao::Tempo.ligada_desde(@definicao)].max
    reunioes = ::Crm::Meeting.where(account_id: @definicao.account_id, status: :scheduled)
                             .where('crm_meetings.starts_at > ? AND crm_meetings.starts_at <= ?', @agora, @agora + antes)
                             .where(MOMENTO, antes.to_i, desde, @agora)
                             .where(card_id: cards.select(:id))
    pagina = @gatilho['pagina_id']
    pagina ? reunioes.where("crm_meetings.metadata ->> 'booking_profile_id' = ?", pagina.to_s) : reunioes
  end

  private

  def cards
    cards = ::Crm::Card.where(account_id: @definicao.account_id)
    cards.where(status: :open).or(cards.com_desfecho(::Autonomia::Automacao::Tempo::Data::DESFECHOS_DO_CARD))
  end
end
