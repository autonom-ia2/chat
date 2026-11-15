# Contrato que o chat2you usa para falar com a máquina de adapters (repo autonomia-adapters).
# Espelha o CLI `autonomia <provider> connection status | capabilities list`. O transporte real
# (HTTP para o serviço do connector) entra na Onda 3; aqui só o contrato + implementação mock.
#
# Retornos são hashes simétricos ao JSON do CLI:
#   open_session      -> { platform:, data: {...}, expires_at:, account_label:, dropped_previous_session: }
#   connection_status -> { status:, account_label:, session_expires_at:, checked_at: }
#   capabilities      -> { platform:, scanned_at:, products: [...] }
#   quote_start       -> { quote_id:, status: queued|running }
#   quote_result      -> { quote_id:, product:, status: running|partial|completed|failed, offers: [...] }
#   quote_proposal    -> { quote_id:, url:, official: }  (official false = resumo impresso, não o documento da seguradora)
#
# CREDENCIAL SÓ EM `open_session`. As demais operações viajam com a sessão que ela devolveu, porque
# cada login novo é uma chamada cara ao portal para receber de volta exatamente a mesma sessão.
#
# (Correção de 11/09/2026: aqui se lia "o portal aceita uma sessão viva por login, e abrir outra
# invalida a anterior — inclusive a de uma cotação em andamento". Medido e falso: sete logins em
# sequência em 05/09 e seis simultâneos em 10/09 compartilharam a MESMA sessão, sem invalidar token
# nenhum. Reusar é economia de login, não exclusividade do portal — e quem serializar cotação por
# corretora com base naquela frase vira o gargalo que o portal não é. Ver `connections/session.rb`.)
#
# `data` é OPACO para nós: guardamos e devolvemos, quem interpreta é o adapter.
# Erros viram Connector::Error (connector/error.rb) com `kind` estável.
class Autonomia::Insurance::Connector::Client
  def open_session(provider:, username:, password:)
    raise NotImplementedError
  end

  def connection_status(provider:, session:)
    raise NotImplementedError
  end

  def capabilities(provider:, session:)
    raise NotImplementedError
  end

  # AS DUAS SEM SESSÃO. São conhecimento do adapter sobre o produto, não tocam no portal, e por
  # isso podem correr dentro do turno: é assim que o agente descobre o que perguntar e confere a
  # entrada ANTES de gastar uma cotação, que no AGGER consome consulta paga. Estavam implementadas
  # nas duas pontas (`Http` e `Mock`) e ausentes deste contrato desde que nasceram.
  #   quote_schema   -> { product:, ramo:, campos: [{ campo:, tipo:, origem:, obrigatorio: }] }
  #   quote_validate -> { valido:, problemas: [{ campo:, severidade:, motivo: }] }
  def quote_schema(provider:, product:)
    raise NotImplementedError
  end

  def quote_validate(provider:, product:, input:)
    raise NotImplementedError
  end

  # SUBMETE e volta rápido, com o id da cotação. Uma cotação leva até ~90s: quem espera é o job
  # assíncrono, consultando `quote_result` — nunca esta chamada.
  def quote_start(provider:, session:, product:, input:)
    raise NotImplementedError
  end

  # UMA consulta. `partial` é o estado que permite entregar ao cliente o que já chegou sem esperar
  # a seguradora mais lenta.
  def quote_result(provider:, session:, quote_id:)
    raise NotImplementedError
  end

  # Sem `insurer_code` é o COMPARATIVO, com todas as seguradoras que cotaram — é o que o cliente
  # recebe por padrão, um PDF só. Com `insurer_code`, a proposta daquela seguradora.
  def quote_proposal(provider:, session:, quote_id:, insurer_code: nil)
    raise NotImplementedError
  end

  # A CARTEIRA DA CORRETORA (E7, #2900): trazer as apólices que a corretora já tem na plataforma, sem cotar nada.
  # Nomes e formas nossos; o que a plataforma chama de quê fica no adapter. Todas com a mesma sessão da cotação, e
  # UM pedido por vez: quem chama não pede páginas em paralelo nem em rajada.
  #   portfolio_sync_start  -> { sync_id:, status: buscando|pronta|falhou }   (desde/ate AAAA-MM-DD, até 37 meses)
  #   portfolio_sync_status -> { status:, por_seguradora: [{ codigo:, nome: (pode ser nil), situacao: }],
  #                              fatias: { pedidas:, total: } (opcional) }
  #                            situacao: pronta | buscando | pede_login | sem_login | falhou
  #                            fatias: o período sai em fatias de um mês, uma por chamada de andamento; o adapter só pede
  #                            a seguinte se a anterior saiu há poucos minutos, então quem chama pergunta logo enquanto
  #                            `pedidas < total` (Carteira::Conector::Sincronizar::ESPERA_DAS_FATIAS).
  #   portfolio_policies    -> { itens: [...], proximo_cursor:, total:, ignorados: }   (com o pedido pronta OU falhou:
  #                            a lista é o que a plataforma já tem, e não depende do robô ter buscado nas seguradoras)
  #   portfolio_document    -> { url: }
  # `sync_id`, `cursor` e `pdf_ref` são opacos: guardamos e devolvemos. O `pdf_ref` e a `url` levam o número da
  # apólice: nunca vão para log, argumento de job, cache ou resposta de API. Item (já em snake_case): ref (pode ser
  # nil), numero, seguradora, ramo, inicio_vigencia, fim_vigencia, emissao, premio_centavos,
  # segurado { nome, documento, email }, item, endosso { numero, data } | nil, parcelas | nil, pdf_ref.
  def portfolio_sync_start(provider:, session:, desde:, ate:)
    raise NotImplementedError
  end

  def portfolio_sync_status(provider:, session:, sync_id:)
    raise NotImplementedError
  end

  def portfolio_policies(provider:, session:, sync_id:, cursor: nil)
    raise NotImplementedError
  end

  def portfolio_document(provider:, session:, ref:)
    raise NotImplementedError
  end
end
