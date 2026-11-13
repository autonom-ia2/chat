# #3006: a situação vem da própria saída, sem prender o contexto do turno na ferramenta memoizada pelo especialista.
module Autonomia::Agents::Tools::LeituraDaPronta
  def situacao_da_pronta(output)
    return unless @record&.pronta?

    dado = JSON.parse(output.to_s)
    dado['situacao'] if dado.is_a?(Hash)
  rescue JSON::ParserError
    # A saída cortada não é JSON: conserva a regra anterior, sem tentar adivinhar pelo texto.
    nil
  end

  # A saída de uma consulta que não chegou na janela: não é dado de sistema (`Answerer#anotar_leitura`).
  def consulta_em_andamento?(output)
    output == ::Autonomia::Agents::Tools::ConsultaNoTurno::EM_ANDAMENTO
  end
end
