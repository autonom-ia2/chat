# Os valores que ficam na execução, não no alvo: o texto da IA (#2679, `ia.<passo>`), o registro criado (G49,
# `criado.<passo>`), a página da agenda (G44) e o dado buscado em outro sistema (#2934, `consulta.<passo>.<chave>`).
# Saiu da Valores no #2934; ela os responde como métodos dela (`extend`).
module Autonomia::Automacao::Valores::DaExecucao
  def da_ia?(caminho)
    prefixo = ::Autonomia::Automacao::Valores::IA
    caminho.to_s.start_with?(prefixo) && caminho.to_s.length > prefixo.length
  end

  # "consulta.p3.status" => ["p3", "status"]; nil fora do prefixo ou sem as duas partes. A chave nunca tem ponto.
  def da_consulta(caminho)
    prefixo = ::Autonomia::Automacao::Valores::CONSULTA
    return unless caminho.to_s.start_with?(prefixo)

    passo_id, _ponto, chave = caminho.to_s.delete_prefix(prefixo).rpartition('.')
    [passo_id, chave] if passo_id.present? && chave.present?
  end

  # O texto da IA (#2679), a página da agenda (G44), o registro criado (G49) e o dado buscado (#2934) valem em qualquer
  # alvo.
  def livre?(caminho)
    da_ia?(caminho) || ::Autonomia::Automacao::AgendaDaPagina.caminho?(caminho) ||
      ::Autonomia::Automacao::RegistroCriado.caminho?(caminho) || da_consulta(caminho).present?
  end

  # "ia.p3" => "p3".
  def passo_da_ia(caminho) = caminho.to_s.delete_prefix(::Autonomia::Automacao::Valores::IA)
end
