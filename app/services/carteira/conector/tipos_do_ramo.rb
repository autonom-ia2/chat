# O tipo do seguro de cada ramo que veio do conector (E7, #2900), pela MESMA decisão da planilha (adendo do Rodrigo de
# 12/11), sem caminho novo de IA:
# 1. o que a CONTA já tem: as apólices guardadas com o mesmo ramo dizem o tipo, o mais frequente
#    (Carteira::Trazer::TipoDoRamo.da_conta);
# 2. o modelo (Carteira::Trazer::PerguntaDoRamo), só com os ramos que sobraram, no mesmo custo e no mesmo registro de uso
#    da planilha. A busca de todo dia quase nunca pergunta: os ramos dela já estão na conta.
# O ramo sem resposta (o modelo falhou, desligado na instalação, "não sei") fica `outro`: o seguro entra, com o ramo como
# veio à vista, e a pessoa corrige na gaveta. Só o nome do ramo vai ao modelo, nunca dado de pessoa.
class Carteira::Conector::TiposDoRamo
  OUTRO = Carteira::Trazer::TipoDoRamo::OUTRO

  def initialize(account, pergunta: nil)
    @account = account
    @pergunta = pergunta
  end

  # ramos: os ramos como vieram. Devolve { ramo agrupado => tipo } de todos eles.
  def call(ramos)
    agrupados = ramos.filter_map { |ramo| agrupado(ramo).presence }.uniq
    return {} if agrupados.empty?

    da_conta = Carteira::Trazer::TipoDoRamo.da_conta(@account.id).slice(*agrupados)
    faltam = agrupados - da_conta.keys
    perguntados = faltam.empty? ? {} : pergunta.call(faltam)
    agrupados.index_with { |ramo| da_conta[ramo] || perguntados[ramo] || OUTRO }
  end

  def agrupado(ramo)
    Carteira::Trazer::TipoDoRamo.agrupado(ramo)
  end

  private

  def pergunta
    @pergunta ||= Carteira::Trazer::PerguntaDoRamo.new(account: @account)
  end
end
