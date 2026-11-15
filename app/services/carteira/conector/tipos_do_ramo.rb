# O tipo do seguro de cada ramo que veio do conector (E7, #2900), pela MESMA decisão da planilha (adendo do Rodrigo de
# 12/11), sem caminho novo de IA:
# 1. o que a CONTA já respondeu, sem perguntar a ninguém: as apólices guardadas com o mesmo ramo dizem o tipo, o mais
#    frequente (Carteira::Trazer::TipoDoRamo.da_conta); o ramo que só está na carteira como `outro` é `outro`; e o tipo
#    que uma busca anterior no conector já respondeu (o item marcado com RESPONDIDO), inclusive quando a resposta foi
#    `outro`. "Buscar de novo" e a busca de todo dia não repetem pergunta;
# 2. o modelo (Carteira::Trazer::PerguntaDoRamo), só com os ramos que sobraram, no mesmo custo e no mesmo registro de uso
#    da planilha.
# `call` devolve só os ramos respondidos. O que ficou sem resposta (o modelo falhou ou está desligado na instalação) fica
# `outro` em quem chama, sem a marca: a próxima busca pergunta de novo. O seguro entra com o ramo como veio à vista, e a
# pessoa corrige na gaveta. Só o nome do ramo vai ao modelo, nunca dado de pessoa.
class Carteira::Conector::TiposDoRamo
  OUTRO = Carteira::Trazer::TipoDoRamo::OUTRO
  # A marca, no item da busca, de que o tipo dele foi respondido (Carteira::Conector::Ler#tipos!).
  RESPONDIDO = 'tipo_respondido'.freeze

  def initialize(account, pergunta: nil)
    @account = account
    @pergunta = pergunta
  end

  # ramos: os ramos como vieram. Devolve { ramo agrupado => tipo } dos que têm resposta.
  def call(ramos)
    agrupados = ramos.filter_map { |ramo| agrupado(ramo).presence }.uniq
    return {} if agrupados.empty?

    sabidos = ja_respondidos.slice(*agrupados)
    faltam = agrupados - sabidos.keys
    faltam.empty? ? sabidos : sabidos.merge(pergunta.call(faltam).slice(*faltam))
  end

  def agrupado(ramo)
    Carteira::Trazer::TipoDoRamo.agrupado(ramo)
  end

  private

  # O tipo que a carteira tem (o mais frequente, fora `outro`) vale sobre o resto.
  def ja_respondidos
    das_buscas.merge(so_outro_na_carteira).merge(Carteira::Trazer::TipoDoRamo.da_conta(@account.id))
  end

  def so_outro_na_carteira
    Carteira::Apolice.where(account_id: @account.id, tipo: OUTRO).where.not(ramo_original: nil).distinct.pluck(:ramo_original)
                     .to_h { |ramo| [agrupado(ramo), OUTRO] }
  end

  def das_buscas
    buscas = Carteira::Leitura.do_conector.where(account_id: @account.id).select(:id)
    respondidos = Carteira::LeituraItem.where(account_id: @account.id, leitura_id: buscas)
                                       .where('carteira_leitura_itens.campos ->> ? IS NOT NULL', RESPONDIDO)
    pares = respondidos.distinct.pluck(Arel.sql("carteira_leitura_itens.campos ->> 'ramo_original'"),
                                       Arel.sql("carteira_leitura_itens.campos ->> 'tipo'"))
    pares.to_h.transform_keys { |ramo| agrupado(ramo) }
  end

  def pergunta
    @pergunta ||= Carteira::Trazer::PerguntaDoRamo.new(account: @account)
  end
end
