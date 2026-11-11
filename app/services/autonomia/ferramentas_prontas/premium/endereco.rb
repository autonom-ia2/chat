# O CEP QUE O CLIENTE NÃO PRECISA SABER (#2858, F7, regra "QI 70" do Rodrigo, 11/11/2026). As consultas do risco do
# endereço vão à BigDataCorp pelo CEP, mas o cliente fala a cidade, ou a rua e o número. Este é o método ÚNICO que acha
# o CEP, e delega ao helper da QI 70 (#2906): o CEP de referência da cidade e a consulta cep/por_endereco, sem duplicá-lo.
#
# -> { 'cep' => '01001000' }; { 'candidatos' => [...] } quando a rua tem mais de um CEP (o agente pergunta o bairro); nil
# quando não achou (o agente pede o CEP).
# Delega a `Fontes::Cep::Referencia.cep`. A Referencia devolve o CEP com traço ("01311-000"); a BigDataCorp recebe só os
# dígitos. `uf` pode vir nil (a cidade única no Brasil basta). `conta`: o id da conta, para a fatia dela no teto do ViaCEP.
module Autonomia::FerramentasProntas::Premium::Endereco
  TAMANHO_DO_CEP = 8

  module_function

  # `rua` nil: o CEP de referência da cidade (a criminalidade é por cidade). Com `rua`: o CEP do endereço.
  def cep(cidade:, uf:, rua: nil, bairro: nil, conta: nil) # rubocop:disable Naming/MethodParameterName
    achado = Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep(cidade: cidade, uf: uf, rua: rua, bairro: bairro, conta: conta)
    return achado unless achado&.key?('cep')

    Autonomia::FerramentasProntas::Parametro.digitos(achado['cep'], TAMANHO_DO_CEP)&.then { |digitos| { 'cep' => digitos } }
  end
end
