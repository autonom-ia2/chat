# frozen_string_literal: true

# A carteira de seguros recusou o que a tela pediu (E4, #2897): falta um campo, a data não é data, o seguro já está
# cancelado, o arquivo não é PDF. A resposta é 422 com o código da recusa em `error`, e só ele: o corpo nunca repete o
# que a pessoa mandou (número de apólice, valor, nome de arquivo). A tela escolhe a frase pelo código.
class CustomExceptions::CarteiraRecusa < CustomExceptions::Base
  def codigo
    @data
  end

  def message
    codigo
  end

  def to_hash
    { error: codigo }
  end

  def http_status
    422
  end
end
