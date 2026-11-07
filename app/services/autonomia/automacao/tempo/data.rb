# card.data e contato.data (#2499, PR3): os cards abertos ou ganhos, ou os contatos, cujo campo de data vale o dia-alvo.
#
# #2678: o card ganho entra (a festa, a revisão e a renovação da apólice vêm depois da venda); o perdido, o cancelado e
# o arquivado não (o cliente foi embora ou o card saiu de cena). Com `repete: todo_ano`, a data compara só o mês e o
# dia, todo ano (aniversário). Quem nasceu em 29/02 é lembrado em 28/02 no ano que não é bissexto; no bissexto, em
# 29/02. A marca leva o dia-alvo com o ano, então dispara uma vez por ano.
#
# A ocorrência é a última `hora` cheia, no fuso da conta, que já passou: hoje, se já passou da hora; senão, ontem.
# Ela cai sempre dentro da janela de 1 dia. A ocorrência anterior a ligar não roda: ligar às 8h um "às 9h" não manda o
# de ontem, e a primeira é a de hoje às 9h. O dia-alvo é o dia da ocorrência mais `dias` (antes: a data ainda vai
# chegar) ou menos `dias` (depois: a data já passou), e entra no SQL como igualdade.
#
# O campo guarda o dia como a tela grava (AAAA-MM-DD); o valor antigo com a hora (AAAA-MM-DDT…) vale pelo dia escrito,
# como a tela mostra (attributeDate.js). Valor em outro formato não casa e é ignorado. Uma vez por dia, a varredura
# conta quantos alvos têm o campo em formato inválido e põe a contagem no log, sem o valor, que é dado do cliente.
class Autonomia::Automacao::Tempo::Data
  # Os 10 primeiros caracteres têm o formato AAAA-MM-DD: só dígitos e hífens, com os hífens no lugar.
  STATUS_DO_CARD = %i[open won].freeze
  FORMATO_DO_DIA = <<~SQL.squish.freeze
    length(left(custom_attributes ->> :campo, 10)) = 10
    AND substr(custom_attributes ->> :campo, 5, 1) = '-' AND substr(custom_attributes ->> :campo, 8, 1) = '-'
    AND translate(left(custom_attributes ->> :campo, 10), '0123456789-', '') = ''
  SQL

  def initialize(definicao:, gatilho:, agora:)
    @definicao = definicao
    @gatilho = gatilho
    @agora = agora
  end

  def cada
    contar_invalidos
    dia = dia_alvo
    return unless dia

    no_dia(dia).find_each do |alvo|
      yield alvo, ::Autonomia::Automacao::Gatilhos.marca_da_data(tipo, alvo, campo, dia)
    end
  end

  def dia_alvo
    local = @agora.in_time_zone(::Autonomia::Automacao::Tempo.fuso(@definicao.account))
    ocorrencia = local.change(hour: @gatilho['hora'].to_i)
    ocorrencia -= 1.day if ocorrencia > local
    return if ocorrencia < ::Autonomia::Automacao::Tempo.ligada_desde(@definicao)

    dias = @gatilho['dias'].to_i
    @gatilho['quando'] == 'antes' ? ocorrencia.to_date + dias : ocorrencia.to_date - dias
  end

  private

  def tipo = @gatilho['tipo']
  def campo = @gatilho['campo']

  def escopo
    return ::Contact.where(account_id: @definicao.account_id) if tipo == 'contato.data'

    ::Crm::Card.where(account_id: @definicao.account_id, status: STATUS_DO_CARD)
  end

  def no_dia(dia)
    return escopo.where('left(custom_attributes ->> ?, 10) = ?', campo, dia.iso8601) unless @gatilho['repete'] == 'todo_ano'

    escopo.where(FORMATO_DO_DIA, campo: campo).where('substr(custom_attributes ->> ?, 6, 5) IN (?)', campo, mes_e_dia(dia))
  end

  # 28/02 de ano que não é bissexto também lembra quem nasceu em 29/02.
  def mes_e_dia(dia)
    mes_dia = dia.strftime('%m-%d')
    mes_dia == '02-28' && !dia.leap? ? [mes_dia, '02-29'] : [mes_dia]
  end

  # Uma vez por automação e dia (a trava no Redis vale 1 dia).
  def contar_invalidos
    return unless Redis::Alfred.set("automacao:tempo:datas_invalidas:#{@definicao.id}:#{@agora.to_date.iso8601}", 1,
                                    nx: true, ex: 1.day.to_i)

    quantos = escopo.where("coalesce(custom_attributes ->> :campo, '') <> ''", campo: campo)
                    .where.not(FORMATO_DO_DIA, campo: campo).count
    return if quantos.zero?

    Rails.logger.warn("[automacao][tempo] datas_invalidas conta=#{@definicao.account_id} automacao=#{@definicao.id} quantos=#{quantos}")
  end
end
