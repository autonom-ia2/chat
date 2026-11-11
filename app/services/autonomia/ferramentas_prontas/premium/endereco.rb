# O CEP QUE O CLIENTE NÃO PRECISA SABER (#2858, F7, regra "QI 70" do Rodrigo, 11/11/2026). As consultas do risco do
# endereço vão à BigDataCorp pelo CEP, mas o cliente fala a cidade, ou a rua e o número. Este é o método ÚNICO que acha
# o CEP: a branch da QI 70 (fix/2858-qi70-prontas) cria o helper do servidor com o CEP de referência da cidade e a
# consulta cep/por_endereco, e a troca acontece só aqui, sem duplicar o helper.
#
# -> { 'cep' => '01001000' }; { 'candidatos' => [...] } quando a rua tem mais de um CEP (o agente pergunta o bairro); nil
# quando não achou (o agente pede o CEP). Até a QI 70 entrar, devolve nil: a interface já aceita a cidade e o endereço,
# e o agente segue pedindo o CEP.
module Autonomia::FerramentasProntas::Premium::Endereco
  module_function

  # `rua` nil: o CEP de referência da cidade (a criminalidade é por cidade). Com `rua`: o CEP do endereço.
  def cep(cidade:, uf:, rua: nil, bairro: nil) # rubocop:disable Lint/UnusedMethodArgument, Naming/MethodParameterName
    nil
  end
end
