# frozen_string_literal: true

# O CPF ou o CNPJ que chegou não foi guardado (épico #1240, decisão R1). A recusa leva o código e uma frase que diz o
# que fazer; nenhum dos dois repete o que a pessoa digitou. Num controller a resposta é 422, com o código em `error`
# (a tela escolhe a frase por ele) e a frase em `message`.
class CustomExceptions::DocumentoRecusa < CustomExceptions::Base
  def codigo
    @data
  end

  def message
    I18n.t("errors.relacionamentos.documento.#{codigo}")
  end

  def to_hash
    { error: codigo, message: message }
  end

  def http_status
    422
  end
end
