# Constrói uma ferramenta nativa ASSÍNCRONA de teste (#313). As nativas de verdade vivem num catálogo
# FECHADO (`Tools::Registry`), então o teste usa uma classe anônima e faz o `Registry.find` apontar
# para ela — mesmo padrão de `spec/services/autonomia/agents/tools/bound_spec.rb`, que já testa as
# síncronas com classe anônima.
module AsyncToolHelper
  # `poll` aceita um Progress fixo ou um lambda que recebe (attempt) e devolve um Progress —
  # é assim que se testa "parcial no 1º, final no 2º".
  # `precheck` aceita texto (o que o modelo recebe no lugar do aceite) ou um callable — que pode
  # levantar, para exercitar "conferência caiu, aceita mesmo assim".
  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- é um construtor de dublê:
  # cada parâmetro é um comportamento que algum exemplo precisa ligar isoladamente.
  # `resultado` e `resta` são as DUAS perguntas do fecho parcial (rodada 6 da entrega 8, P1-B). O
  # padrão é o do `Base` — false, false —, e é ele que faz a ferramenta genérica fechar em SILÊNCIO
  # em vez de afirmar que algo ficou pelo caminho.
  def build_async_tool(slug: 'consultar_cotacao', handle: { 'id' => 'cot-1' }, poll: nil,
                       start_error: nil, poll_error: nil, precheck: nil, closing: nil,
                       resultado: false, resta: false)
    Class.new(::Autonomia::Agents::Tools::Native::Base) do
      define_singleton_method(:slug) { slug }
      define_singleton_method(:description) { 'Ferramenta assíncrona de teste.' }
      define_singleton_method(:async?) { true }
      define_singleton_method(:accepted_message) { 'aceito: consulta iniciada' }
      define_singleton_method(:waiting_message) { 'estou consultando agora' }
      define_singleton_method(:failure_message) { 'não consegui concluir a consulta' }
      define_singleton_method(:uncertain_message) { 'não consegui confirmar o envio' }

      # A conferência do turno: devolve texto ao modelo (e nenhuma execução é aberta) ou nil.
      define_method(:precheck) { precheck.respond_to?(:call) ? precheck.call : precheck }

      # O que ainda vale entregar quando a execução acaba sem fechar (o comparativo, na cotação).
      # `trabalho_novo:` é do contrato desde a rodada 6 e o dublê genérico o ignora: quem o observa
      # é `encerramento_spec`, que define o método por conta própria.
      define_method(:closing_deliveries) do |_handle, **|
        closing.respond_to?(:call) ? closing.call : Array(closing)
      end

      define_method(:resultado_entregue?) { |_handle| resultado }
      define_method(:resta_entregar?) { |_handle| resta }

      define_method(:start) do
        raise start_error if start_error

        handle
      end

      define_method(:poll) do |**kwargs|
        raise poll_error if poll_error

        poll.respond_to?(:call) ? poll.call(kwargs[:attempt]) : poll
      end
    end
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  # Faz o catálogo devolver esta ferramenta para o slug dela (e nada para os outros).
  def register_async_tool(tool)
    allow(::Autonomia::Agents::Tools::Registry).to receive(:find) do |slug|
      slug.to_s == tool.slug ? tool : nil
    end
    allow(::Autonomia::Agents::Tools::Registry).to receive(:for_agent).and_return([tool])
    tool
  end
end

RSpec.configure do |config|
  config.include AsyncToolHelper
end
