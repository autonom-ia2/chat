# O que muda numa cotação de auto quando o cliente JÁ TEM seguro.
#
# Mora fora da ferramenta porque é regra de negócio com armadilhas próprias, e porque a ferramenta
# de cotação já carrega o ciclo assíncrono inteiro. Aqui só entra a leitura do que o modelo mandou.
#
# O portal cobra menos de quem renova, e a conta sai de três campos. Sem eles a renovação é cotada
# como a primeira apólice da vida do cliente — mais cara — e o comparativo perde para o preço que
# ele já paga hoje, por um motivo que não existe.
class Autonomia::Insurance::AutoRenewal
  # Faixa que o adapter aceita. Fora dela o `safeParse` dele RECUSA a cotação inteira, antes de
  # qualquer chamada ao portal: vira 422, o job entra em retry, e o cliente espera os 420 s do
  # deadline para receber "não consegui concluir". Por um inteiro errado.
  BONUS_RANGE = (0..10)

  # O cast do Rails trata só `false/0/f/off` como falso — `"não"` e `"nao"` viram TRUE. Numa
  # ferramenta cujos parâmetros e conversa são em português, essa é a string errada mais provável
  # que o modelo pode mandar, e ela cotaria como renovação um cliente que acabou de dizer que não é.
  NEGATIVAS_PT = %w[nao não n no nenhum].freeze

  def initialize(params)
    @params = params.to_h
  end

  def renovacao?
    valor = @params['renovacao']
    return false if valor.is_a?(String) && NEGATIVAS_PT.include?(valor.strip.downcase)

    ActiveModel::Type::Boolean.new.cast(valor).present?
  end

  # Renovação em que não sabemos a classe. O portal vai precificar como quem nunca teve seguro, e o
  # cliente tem direito de saber que existe preço melhor esperando por um dado que ele pode buscar.
  def sem_bonus?
    renovacao? && bonus.nil?
  end

  # -> Hash para dar `merge` no input da cotação. Vazio quando não é renovação.
  #
  # ATENÇÃO: omitir o bloco NÃO é proteção. Medido contra o schema do adapter: `bonusClass` tem
  # `.default(0)` e o payload escreve `bonusAnterior` incondicionalmente, então omitir e mandar zero
  # chegam idênticos ao portal. Quem consertar "renovação sem bônus" mexe na COLETA, não aqui.
  def to_input
    return {} unless renovacao?

    dados = { 'isRenewal' => true }
    dados['bonusClass'] = bonus unless bonus.nil?
    dados['previousClaimsCount'] = sinistros unless sinistros.nil?
    { 'quotation' => dados }
  end

  private

  # -> Integer na faixa, ou nil quando o cliente não soube (e quando o modelo mandou o que não é
  # classe de bônus).
  #
  # Fora da faixa vira NIL, não vira 10. Limitar a 10 inventaria um bônus que o cliente não tem e
  # devolveria um preço que ele não consegue comprar — mentira que só aparece na emissão. Sem bônus
  # a cotação sai mais cara e verdadeira, e o cliente é avisado de que dá para melhorar.
  #
  # ZERO é resposta, não ausência: quem teve sinistro volta para a classe 0. Por isso `nil` e `0`
  # levam a caminhos diferentes.
  def bonus
    return @bonus if defined?(@bonus)

    bruto = @params['bonus']
    @bonus = bruto.present? && BONUS_RANGE.cover?(bruto.to_i) ? bruto.to_i : nil
  end

  # String vazia é o modelo dizendo "não sei"; `0` é o cliente dizendo que não teve sinistro.
  def sinistros
    valor = @params['sinistros']
    valor.present? ? valor.to_i : nil
  end
end
