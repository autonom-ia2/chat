# O que muda numa cotação de auto quando o cliente JÁ TEM seguro.
#
# O portal cobra menos de quem renova, e a conta sai de três campos. Sem eles a renovação é cotada
# como a primeira apólice da vida do cliente — mais cara — e o comparativo perde para o preço que
# ele já paga hoje, por um motivo que não existe.
#
# ESTA CLASSE NÃO VALIDA O QUE O MODELO ENTENDEU. O schema da função declara `boolean` e `integer`,
# e quem interpreta "não sei", "uns 30%" ou "acho que é 5" é o próprio agente, que tem contexto da
# conversa e a descrição de cada parâmetro para se guiar. Encher isto de allowlist de sinônimos e
# parser de texto seria refazer, pior, o trabalho que o modelo já faz.
#
# A ÚNICA guarda aqui é de FAIXA, e existe por um motivo que não é interpretativo: o adapter valida
# com zod e RECUSA a cotação inteira quando o número está fora do intervalo — antes de qualquer
# chamada ao portal. Isso vira 422, o job entra em retry, e o cliente espera os 420 s do deadline
# para receber "não consegui concluir". Um número fora da faixa não deve custar sete minutos de
# silêncio ao cliente; deve custar uma cotação sem bônus, que é recuperável e vem com aviso.
class Autonomia::Insurance::AutoRenewal
  # Exatamente as faixas de `quote-input.ts`. As duas, porque o defeito é da classe e não do campo:
  # a primeira versão guardava só o bônus, e `sinistros: -1` derrubava a cotação do mesmo jeito.
  # A DESCRIÇÃO QUE O AGENTE LÊ. Mora aqui, e não na ferramenta, porque é a mesma regra que esta
  # classe aplica: quem ensina e quem valida não podem divergir.
  #
  # A descrição de um parâmetro é ONDE SE ENSINA A REGRA DE NEGÓCIO ao agente, e não onde se manda
  # ele desistir. O cliente quase nunca sabe dizer "classe 5" — ele conta a história ("tenho seguro
  # há três anos e nunca bati"), e o dado está ali inteiro. Traduzir isso é o trabalho do agente.
  #
  # A tabela abaixo é do Rodrigo (PO), ditada em 05/09/2026. Antes disso o código carregava uma
  # tabela parecida sem fonte nenhuma, e com um exemplo INVENTADO e errado ("6 anos, um sinistro ->
  # classe 1"; pela regra é 6 menos 1, classe 5).
  BONUS_DESC = 'Classe de bônus da apólice atual, de 0 a 10. Só em renovação. REGRA: a classe é o ' \
               'número de anos de seguro sem sinistro, e cai 1 a cada sinistro ocorrido na ' \
               'vigência atual. Acima de 10 anos, continua 10. Seguro novo é 0. Cada classe vale ' \
               'um desconto: 0=0%, 1=10%, 2=15%, 3=20%, 4=25%, 5 a 10=30%. ' \
               'DEDUZA da conversa, sem exigir o termo técnico: "tenho seguro há 3 anos e nunca ' \
               'bati" é classe 3; "renovo há 6 anos e bati uma vez este ano" é classe 5; se ele ' \
               'souber só o desconto, use a tabela ao contrário. ZERO é resposta válida: quem teve ' \
               'sinistro na primeira vigência volta para 0. Só deixe em branco quando não houver ' \
               'NADA na conversa de onde deduzir; aí a cotação sai sem bônus e o cliente é avisado ' \
               'de que dá para melhorar.'.freeze

  SINISTROS_DESC = 'Quantos sinistros o cliente teve na vigência atual — é o que derruba a classe ' \
                   'de bônus, 1 por sinistro. Só em renovação. Deduza da conversa: "nunca bati", ' \
                   '"nunca usei o seguro" e "sem ocorrência" são 0. Zero é resposta comum, e não ' \
                   'é o mesmo que não saber.'.freeze

  BONUS_RANGE = (0..10)
  SINISTROS_RANGE = (0..99)

  def initialize(params)
    @params = params.to_h.deep_stringify_keys
  end

  def renovacao?
    ActiveModel::Type::Boolean.new.cast(@params['renovacao']).present?
  end

  # Renovação em que não sabemos a classe. O portal precifica como quem nunca teve seguro, e o
  # cliente tem direito de saber que existe preço melhor esperando por um dado que ele pode buscar.
  def sem_bonus?
    renovacao? && bonus.nil?
  end

  # -> Hash para dar `merge` no input da cotação. Vazio quando não é renovação.
  #
  # Omitir o bloco NÃO protege ninguém: o adapter tem `.default(0)` e escreve `bonusAnterior`
  # incondicionalmente, então omitir e mandar zero chegam idênticos ao portal. Quem cuida do caso
  # "renovação sem bônus" é o aviso ao cliente, não esta omissão.
  def to_input
    return {} unless renovacao?

    dados = { 'isRenewal' => true }
    dados['bonusClass'] = bonus unless bonus.nil?
    dados['previousClaimsCount'] = sinistros unless sinistros.nil?
    { 'quotation' => dados }
  end

  private

  # Fora da faixa vira NIL, não vira 10. Limitar inventaria um bônus que o cliente não tem e
  # devolveria um preço que ele não consegue comprar — mentira que só aparece na emissão.
  #
  # ZERO é resposta, não ausência: quem teve sinistro volta para a classe 0.
  def bonus
    @bonus = na_faixa(@params['bonus'], BONUS_RANGE) unless defined?(@bonus)
    @bonus
  end

  def sinistros
    @sinistros = na_faixa(@params['sinistros'], SINISTROS_RANGE) unless defined?(@sinistros)
    @sinistros
  end

  def na_faixa(valor, faixa)
    return nil if valor.blank? && valor != 0

    numero = valor.to_i
    numero if faixa.cover?(numero)
  end
end
