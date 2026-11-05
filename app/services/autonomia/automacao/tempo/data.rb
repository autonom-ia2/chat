# card.data e contato.data (#2499, PR3): os cards abertos ou os contatos cujo campo de data vale o dia-alvo.
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

    escopo.where('left(custom_attributes ->> ?, 10) = ?', campo, dia.iso8601).find_each do |alvo|
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

    ::Crm::Card.where(account_id: @definicao.account_id, status: :open)
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
