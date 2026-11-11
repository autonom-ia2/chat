# O CPF conferido aqui, sem rede: dígitos verificadores e a região fiscal. Número inválido é resposta ("não é válido"),
# não "não encontrado": o agente pede ao cliente para conferir.
class Autonomia::FerramentasProntas::Fontes::Cpf::Calculo < Autonomia::FerramentasProntas::Provedor
  NOME = 'calculo'.freeze
  HOST = nil

  def consultar(_consulta, params)
    cpf = params.fetch('cpf')
    return { 'valido' => false, 'observacao' => 'Os dígitos verificadores não conferem: confira o número com o cliente.' } unless
      Autonomia::FerramentasProntas::Fontes::Cpf.valido?(cpf)

    { 'valido' => true }.merge(Autonomia::FerramentasProntas::Fontes::Cpf.regiao(cpf))
                        .merge('observacao' => 'Só o número foi conferido: nome e situação na Receita não fazem parte.')
  end
end
