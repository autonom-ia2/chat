# QUEM FICOU SEM PROPOSTA, E POR QUÊ, PARA A EQUIPE (chat#612 e #638, decisões do CEO de 23 e 24/09/2026).
#
# A Lia não fala com o cliente de quem ficou sem proposta: nem recusa, nem prazo, nem instabilidade. Diz só que a
# seguradora não trouxe proposta desta vez, e, quando nenhuma trouxe, que vai encaminhar para alguém da equipe
# (`Eventos`, `sem_aceitacao`). Quem assume precisa saber o motivo de cada uma, e ele está no resultado guardado: o
# texto que a seguradora escreveu ao recusar, a instabilidade que o conector apontou, ou a falta de resposta até o fim.
# No fecho da cotação isso vira NOTA INTERNA da conversa (`Tools::NotaInterna`): o cliente não a vê, e o modelo também
# não (o histórico da Lia e o do CRM leem só mensagens públicas).
module Autonomia::Agents::Tools::Native::InsuranceQuote::NotaDaEquipe
  extend ActiveSupport::Concern

  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora

  CABECALHO = 'Seguradoras sem proposta na cotação de %<cotacao>s (execução %<run>s). A IA não fala delas com o cliente. ' \
              'O motivo de cada uma:'.freeze
  RECUSOU = 'recusou e escreveu no portal: "%<texto>s"'.freeze
  INSTAVEL = 'estava instável no portal e não respondeu'.freeze
  SEM_RESPOSTA = 'não respondeu até o fim da cotação'.freeze
  CREDENCIAL = 'o portal recusou a credencial da corretora nesta seguradora'.freeze
  SEM_MOTIVO = 'não trouxe proposta, e o portal não disse por quê'.freeze

  # -> nenhuma seguradora trouxe preço, e ao menos uma recusou escrevendo o motivo? Então o desfecho é
  # `sem_aceitacao`: nada falhou, e a Lia não diz que a cotação não pôde ser feita.
  def sem_aceitacao?(handle)
    entradas = entradas_de(handle)
    entradas.none? { |entrada| entrada['desfecho'] == Guardado::COM_PRECO } &&
      entradas.any? { |entrada| recusa_escrita?(entrada) }
  end

  # -> o texto da nota interna, ou nil quando todas as seguradoras trouxeram preço (ou nada foi guardado). Lido no
  # fecho: quem ainda aguardava ali não respondeu até o fim.
  def nota_da_equipe(handle)
    sem_proposta = entradas_de(handle).reject { |entrada| entrada['desfecho'] == Guardado::COM_PRECO }
    return if sem_proposta.empty?

    cabecalho = format(CABECALHO, cotacao: cotacao_da_nota, run: run.id)
    [cabecalho, *sem_proposta.map { |entrada| "- #{entrada['nome']}: #{motivo_para_a_equipe(entrada)}" }].join("\n")
  end

  private

  def entradas_de(handle)
    handle.to_h[self.class::RESULTADO_KEY].to_h.values.map(&:to_h)
  end

  def recusa_escrita?(entrada)
    entrada['desfecho'] == Guardado::SEM_PROPOSTA && entrada[Guardado::TEXTO].present?
  end

  def motivo_para_a_equipe(entrada)
    return format(RECUSOU, texto: entrada[Guardado::TEXTO]) if recusa_escrita?(entrada)
    return SEM_RESPOSTA if entrada['desfecho'] == Guardado::AGUARDANDO
    return INSTAVEL if entrada['motivo'] == ::Autonomia::Insurance::MotivoDaRecusa::INSTABILIDADE
    return CREDENCIAL if entrada[Guardado::CONTA_DA_CORRETORA]

    SEM_MOTIVO
  end

  # O ramo e o bem, como a equipe os lê ("auto, Nivus").
  def cotacao_da_nota
    item = run.arguments.to_h.stringify_keys['item'].to_s.squish.presence
    [::Autonomia::Insurance::Faixa.ramo(run.faixa).presence || 'auto', item].compact.join(', ')
  end
end
