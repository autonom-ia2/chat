# O QUE AS SEGURADORAS ESCREVERAM AO RECUSAR, PARA A EQUIPE (chat#612, decisão do CEO de 23/09/2026).
#
# A Lia não fala de recusa do risco com o cliente: diz só que a seguradora não trouxe proposta desta vez, e, quando
# nenhuma trouxe, que vai encaminhar para alguém da equipe (`Eventos`, `sem_aceitacao`). Quem assume precisa saber por
# quê, e o motivo está no texto do portal. No fecho da cotação ele vira NOTA INTERNA da conversa (`Tools::NotaInterna`):
# o cliente não a vê, e o modelo também não (o histórico da Lia e o do CRM leem só mensagens públicas).
module Autonomia::Agents::Tools::Native::InsuranceQuote::NotaDaEquipe
  extend ActiveSupport::Concern

  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora

  CABECALHO = 'Recusas da cotação de %<cotacao>s (execução %<run>s). A IA não contou o motivo ao cliente: disse só que ' \
              'a seguradora não trouxe proposta desta vez. O que cada uma escreveu no portal:'.freeze

  # -> nenhuma seguradora trouxe preço, e ao menos uma recusou escrevendo o motivo? Então o desfecho é
  # `sem_aceitacao`: nada falhou, e a Lia não diz que a cotação não pôde ser feita.
  def sem_aceitacao?(handle)
    entradas = handle.to_h[self.class::RESULTADO_KEY].to_h.values.map(&:to_h)
    entradas.none? { |entrada| entrada['desfecho'] == Guardado::COM_PRECO } && recusas_escritas(entradas).any?
  end

  # -> o texto da nota interna, ou nil quando nenhuma seguradora escreveu motivo de recusa.
  def nota_da_equipe(handle)
    recusas = recusas_escritas(handle.to_h[self.class::RESULTADO_KEY].to_h.values.map(&:to_h))
    return if recusas.empty?

    cabecalho = format(CABECALHO, cotacao: cotacao_da_nota, run: run.id)
    [cabecalho, *recusas.map { |nome, texto| "- #{nome}: \"#{texto}\"" }].join("\n")
  end

  private

  # O ramo e o bem, como a equipe os lê ("auto, Nivus").
  def cotacao_da_nota
    item = run.arguments.to_h.stringify_keys['item'].to_s.squish.presence
    [::Autonomia::Insurance::Faixa.ramo(run.faixa).presence || 'auto', item].compact.join(', ')
  end

  def recusas_escritas(entradas)
    entradas.filter_map do |entrada|
      [entrada['nome'], entrada[Guardado::TEXTO]] if entrada['desfecho'] == Guardado::SEM_PROPOSTA && entrada[Guardado::TEXTO].present?
    end
  end
end
