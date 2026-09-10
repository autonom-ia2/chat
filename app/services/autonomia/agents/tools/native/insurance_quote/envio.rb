# A CHAMADA PAGA, e a fronteira de incerteza em volta dela (entrega 5).
#
# `quote_start` é a única chamada da cotação que custa dinheiro e deixa registro no portal do
# corretor. O que falha ANTES dela (login, conexão ausente, validação) ou COM o portal dizendo que
# recusou (credencial, entrada) é falha comum: nada foi cotado. O que falha DEPOIS de ela sair sem o
# portal dizer nada — timeout, 502/503, resposta que não se lê — é outra coisa: a cotação pode
# existir lá. Até 10/09/2026 o job lia as duas como "não fez" e apagava a intenção de submeter; a
# passada seguinte cotava de novo, sem marca. Era a janela #337 por outra porta.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Envio
  extend ActiveSupport::Concern

  # As categorias em que o portal DISSE que não cotou, ou nem foi chamado: credencial recusada (401,
  # antes de processar), entrada recusada, conexão sem configuração, ramo que o adapter não tem.
  # `auth_required` sobe como está porque `with_fresh_session` a reconhece: renova a sessão e chama
  # de novo. Tudo o que não está aqui vira `Native::EnvioIncerto`.
  NAO_ENVIOU = %i[auth_required validation config not_implemented].freeze

  private

  # -> o id da cotação no portal. Levanta `EnvioIncerto` quando a chamada saiu e não se sabe o que o
  # portal fez com ela — inclusive quando ele respondeu algo sem id.
  def enviar(open_session, pedido)
    resposta = chamar_portal(open_session, pedido)
    quote_id = resposta.is_a?(Hash) ? resposta['quote_id'].presence : nil
    quote_id || raise(::Autonomia::Agents::Tools::Native::EnvioIncerto, 'resposta sem quote_id')
  end

  def chamar_portal(open_session, pedido)
    connector.quote_start(session: open_session, **pedido)
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise if NAO_ENVIOU.include?(e.kind)

    raise ::Autonomia::Agents::Tools::Native::EnvioIncerto, e.kind
  rescue StandardError => e
    raise ::Autonomia::Agents::Tools::Native::EnvioIncerto, e.class.name
  end
end
