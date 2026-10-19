# O mês de CRM › Números (#1897, F3 do #1871). Um relógio só: o mês no fuso da conta (Crm::Timezone::Resolver, F1).
# A chave chega como "AAAA-MM"; vazia é o mês de hoje. Mês futuro, mais antigo que o limite ou fora do formato é recusado.
class Crm::Numeros::Mes
  class Invalido < StandardError; end

  MESES_ATRAS = 12

  attr_reader :inicio

  def initialize(account:, chave: nil)
    @zone = Crm::Timezone::Resolver.new(account: account).zone_or_default
    @hoje = @zone.now
    @inicio = chave.blank? ? @hoje.beginning_of_month : ler(chave.to_s)
  end

  def range
    inicio..(fechado? ? inicio.end_of_month : @hoje)
  end

  def fechado?
    inicio < @hoje.beginning_of_month
  end

  def info
    dias = inicio.end_of_month.day
    dia = fechado? ? dias : @hoje.day
    {
      chave: chave_de(inicio), dia: dia, diasNoMes: dias, diasRestantes: dias - dia, fechado: fechado?,
      anterior: inicio > limite ? chave_de(inicio.prev_month) : nil,
      seguinte: fechado? ? chave_de(inicio.next_month) : nil
    }
  end

  private

  def limite
    @hoje.beginning_of_month - MESES_ATRAS.months
  end

  def chave_de(momento)
    momento.strftime('%Y-%m')
  end

  def ler(chave)
    ano, mes, *resto = chave.split('-')
    raise Invalido unless resto.empty? && digitos?(ano, 4) && digitos?(mes, 2) && (1..12).cover?(mes.to_i)

    inicio = @zone.local(ano.to_i, mes.to_i, 1)
    raise Invalido if inicio > @hoje || inicio < limite

    inicio
  end

  def digitos?(parte, tamanho)
    parte.to_s.length == tamanho && parte.count('0-9') == tamanho
  end
end
