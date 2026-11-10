# As conferências do `de_novo.desde` ao salvar (G46, o laço dos documentos do exemplo 14). O caminho marcado volta ao
# "esperar até" `desde` (Roteiro). O laço acaba por construção porque:
# - o `desde` é um "esperar até" irmão anterior do "decidir", na mesma lista: a volta passa de novo por ele;
# - a condição dele só vale com uma mensagem nova do cliente, `conversa.cliente_respondeu` ou
#   `conversa.cliente_mandou_documento` igual a verdadeiro (direto, numa das `todas`, ou em todas as `alguma`): toda
#   volta espera o cliente, e o laço nunca gira pago sem ele. O prazo vencido sai pelo "se vencer" do próprio "esperar".
module Autonomia::Automacao::DecidirDeNovo::Desde
  module_function

  DO_CLIENTE = %w[conversa.cliente_respondeu conversa.cliente_mandou_documento].freeze

  def problemas(passo, receita)
    desde = passo.dig('de_novo', 'desde')
    return [] if desde.blank?

    roteiro = ::Autonomia::Automacao::Roteiro.new(receita)
    espera = roteiro.passo(desde)
    return [texto(:de_novo_desde_desconhecido, passo: passo['id'], desde: desde)] unless espera
    return [texto(:de_novo_desde_nao_anterior, passo: passo['id'], desde: desde)] unless anterior?(espera, passo, roteiro)

    espera_o_cliente?(espera['condicao']) ? [] : [texto(:de_novo_desde_sem_resposta, passo: passo['id'], desde: desde)]
  end

  def anterior?(espera, passo, roteiro)
    espera['tipo'] == 'esperar_ate' && roteiro.anteriores(passo['id']).any? { |irmao| irmao.equal?(espera) }
  end

  def espera_o_cliente?(condicao)
    return false unless condicao.is_a?(Hash)
    return Array(condicao['todas']).any? { |filha| espera_o_cliente?(filha) } if condicao.key?('todas')
    return Array(condicao['alguma']).all? { |filha| espera_o_cliente?(filha) } if condicao.key?('alguma')

    mensagem_nova?(condicao)
  end

  def mensagem_nova?(condicao)
    DO_CLIENTE.include?(condicao.dig('campo', '$valor')) && condicao['op'] == 'igual' && condicao['valor'] == true
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
