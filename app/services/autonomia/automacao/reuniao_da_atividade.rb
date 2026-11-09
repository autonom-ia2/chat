# A reunião de uma atividade do card (G12, G32): a atividade de reunião marcada, remarcada ou cancelada guarda o id da
# reunião no payload. Sempre presa ao card e à conta (parecer da Funções, G12), nunca só pelo id.
#
# Quem usa: o Contexto, para a reunião do gatilho que a receita lê (`reuniao.*`) e para quem atende ela (avisar); a
# Escuta, para a página de agendamento em que ela foi marcada (o filtro `pagina_id` dos gatilhos de reunião, G32) e
# para saber se o resultado da reunião começa a "reunião atendida" (G56).
module Autonomia::Automacao::ReuniaoDaAtividade
  # A página de agendamento fica na reunião marcada por ela (Crm::BookingV2::Booker).
  PAGINA = 'booking_profile_id'.freeze

  module_function

  def de(card, atividade_id)
    reuniao_id = payload(card, atividade_id)['meeting_id']
    reuniao_id && card.account.crm_meetings.find_by(id: reuniao_id, card_id: card.id)
  end

  # G56: o resultado da reunião só começa a "reunião atendida" no primeiro "Aconteceu"; os outros só acordam a espera
  # (Escuta#comecar_no_card). Os demais gatilhos do card começam sempre.
  def comeca?(tipo, card, atividade_id)
    tipo != ::Autonomia::Automacao::Gatilhos::ATENDIDA || atendida_agora?(card, atividade_id)
  end

  # G56: a atividade é o primeiro "Aconteceu" da reunião (Crm::Meetings::RecordOutcomeService grava `first_held`).
  # "Não compareceu", salvar as anotações de novo e voltar para "Aconteceu" depois de trocar não disparam.
  def atendida_agora?(card, atividade_id)
    dados = payload(card, atividade_id)
    dados['outcome'] == 'held' && dados['first_held'] == true
  end

  def payload(card, atividade_id)
    atividade = atividade_id && ::Crm::Activity.find_by(id: atividade_id, account_id: card.account_id, card_id: card.id)
    atividade&.payload.to_h
  end

  # O lembrete (#2709) não tem atividade: a reunião vem da marca da execução, presa ao card e à conta do mesmo jeito.
  # Só a agendada: cancelada entre a varredura e o passo, o lembrete não lê a reunião (o passo que a pede pula).
  def do_lembrete(card, marca)
    reuniao_id = ::Autonomia::Automacao::Gatilhos.reuniao_da_marca(marca)
    reuniao_id && card.account.crm_meetings.find_by(id: reuniao_id, card_id: card.id, status: :scheduled)
  end

  # O id da página em que a reunião foi marcada; nil quando foi marcada na tela. A IA marca pela página
  # (o Booker grava o id), então a reunião dela tem a página.
  def pagina(reuniao) = reuniao&.metadata.to_h[PAGINA]

  # O parâmetro `pagina_id` dos gatilhos de reunião, para a Escuta casar o filtro; vazio nos outros gatilhos.
  def do_gatilho(tipo, card, atividade_id)
    return {} unless ::Autonomia::Automacao::Gatilhos.de_reuniao?(tipo)

    { 'pagina_id' => pagina(de(card, atividade_id)) }
  end
end
