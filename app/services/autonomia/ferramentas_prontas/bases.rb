# AS BASES QUE A PLATAFORMA BAIXA E MANTÉM ATUALIZADAS (#2858, F5): planos de saúde (ANS), aeronaves (RAB da ANAC),
# geração distribuída (ANEEL), transportadoras (RNTRC da ANTT) e focos de queimada (INPE).
#
# Cada base tem um IMPORTADOR (`Bases::<Nome>`, subclasse de `Importador`): de onde baixa, com que teto, de quanto em
# quanto tempo e como cada linha do arquivo vira linha da tabela. A `Importacao` faz o resto, igual para todas: baixa
# por streaming com teto, grava a geração nova ao lado da que vale, confere, troca e apaga a antiga. Falhou: a cópia
# anterior continua valendo e a equipe recebe o alerta (`Alerta`).
#
# Quem consulta é a fonte do catálogo de cada base (`Fontes::PlanosDeSaude`...), com um provedor local (`Bases::Provedor`,
# sem rede): a busca é no banco, nunca na fonte oficial.
#
# A flag `agente_ferramentas_prontas_bases` liga as cinco fontes no catálogo. Sem nenhuma conta com ela, nada é baixado.
module Autonomia::FerramentasProntas::Bases
  FLAG = 'agente_ferramentas_prontas_bases'.freeze

  # Uma falha da importação, com um motivo curto do código (nunca texto de fora): vai ao estado e ao alerta.
  class Falha < StandardError
    def motivo
      message
    end
  end

  module_function

  # A ordem da rodada: as diárias pequenas primeiro (os focos de queimada, que envelhecem em 1 dia; planos de saúde;
  # aeronaves), depois as mensais grandes.
  def importadores
    [Queimadas, PlanosDeSaude, Aeronaves, GeracaoSolar, Transportadoras]
  end

  def buscar(chave)
    importadores.find { |importador| chave.to_s == importador::CHAVE }
  end

  # Alguma conta usa as bases? Sem nenhuma, o job não baixa nada.
  def em_uso?
    Account.feature_agente_ferramentas_prontas_bases.exists?
  end
end
