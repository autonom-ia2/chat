# Os campos de um seguro que a tela corrige (E4, #2897) e a coluna de cada um na apólice. Os nomes da tela são os que a
# história (`mudancas`) e `corrigido_a_mao` guardam; os valores ficam na forma do banco, sem depender de formato de
# tela: o valor em centavos e a data como AAAA-MM-DD. Quem desfaz repõe a coluna com o que está guardado.
#
# E8.1 (#3043): os dados do segurado da cotação (nascimento, sexo, CEP, placa e classe de bônus). Nascimento, sexo e CEP
# são dado pessoal (PESSOAIS): a história guarda só QUE mudaram, nunca o valor, nem o de antes, nem o de depois. Para o
# desfazer, guarda só se antes estava vazio (`antes_vazio`): aí desfazer é apagar; com valor antes, não há o que repor, e
# quem desfaz deixa o seguro como está (`desfeito`).
module Carteira::Campos
  COLUNAS = {
    'tipo' => :tipo, 'seguradora' => :seguradora, 'numero' => :numero, 'comeca' => :inicio_vigencia,
    'termina' => :fim_vigencia, 'valor' => :valor_centavos, 'bem' => :bem,
    'nascimento' => :segurado_nascimento, 'sexo' => :segurado_sexo, 'cep' => :cep, 'placa' => :placa, 'bonus' => :bonus_classe
  }.freeze
  VALOR = 'valor'.freeze
  CENTAVOS_POR_REAL = 100
  PESSOAIS = %w[nascimento sexo cep].freeze
  ANTES_VAZIO = 'antes_vazio'.freeze

  module_function

  # O valor de uma coluna como a história guarda.
  def guardado(valor)
    valor.is_a?(Date) ? valor.iso8601 : valor
  end

  # Uma mudança como a história guarda: o antes e o depois, ou, no dado pessoal, só se antes estava vazio.
  def mudanca(campo, antes, depois)
    return { campo: campo, antes: antes, depois: depois } unless PESSOAIS.include?(campo)

    { campo: campo, antes_vazio: antes.nil? }
  end

  # Para quem desfaz uma mudança da história (com as chaves em texto, como o banco devolve): `agora` é o valor da coluna
  # hoje. -> [true, valor de antes] quando a coluna ainda está como a mudança deixou; [false, nil] quando não dá para
  # desfazer. O dado pessoal só se desfaz quando antes estava vazio (e hoje tem valor): volta a ser vazio.
  def desfeito(mudanca, agora)
    return [mudanca[ANTES_VAZIO] == true && !agora.nil?, nil] if PESSOAIS.include?(mudanca['campo'])

    [agora == mudanca['depois'], mudanca['antes']]
  end

  def em_reais(centavos)
    centavos && (centavos.to_f / CENTAVOS_POR_REAL)
  end
end
