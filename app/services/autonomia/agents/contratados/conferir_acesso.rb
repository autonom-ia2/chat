# Confere o login do corretor na Universal pelo Setup e grava no acesso do agente contratado (#3211) SÓ o login que a
# Universal aceitou. Nunca levanta o erro do cliente: o que volta é o resultado da conferência.
#
# A CONFERÊNCIA QUE NÃO DEU CERTO NÃO GRAVA NADA (recusada, sem resposta ou pedido que a Universal não aceitou): o
# acesso que já funcionava (login, senha, estado, capacidades e a data da conferência) fica como estava, e sem acesso
# gravado nenhuma linha nasce. É o que a tela promete ("Nada foi guardado"): uma tentativa errada ao trocar o login não
# derruba o agente que já atende com o login antigo.
class Autonomia::Agents::Contratados::ConferirAcesso
  Codigos = Autonomia::Seguradoras::Universal::Codigos

  # Nome do campo no Setup da Universal => a nossa chave em `capacidades`. Os nomes da esquerda são os do levantamento
  # de fatos (o resumo da coleção Postman não traz o Setup); a Tarefa 0b os confere na resposta real.
  CAPACIDADES = { 'soCotacao' => 'so_cotacao', 'emiteFaturado' => 'emite_faturado',
                  'emiteBoleto' => 'emite_boleto', 'tarifaAcordo' => 'tarifa_acordo' }.freeze

  # Erro do cliente => estado do acesso. `pedido_invalido` no Setup não é recusa de acesso: o login não foi julgado.
  ESTADO_POR_CODIGO = { Codigos::ACESSO_RECUSADO => 'recusado' }.freeze
  ESTADO_PADRAO = 'nao_conferido'.freeze

  def initialize(agent:, login:, senha:)
    @agent = agent
    @login = login
    @senha = senha
  end

  # -> AcessoDaSeguradora: a linha gravada, quando a Universal aceitou o login; senão, o resultado desta tentativa, sem
  # gravar (e sem o login nem a senha dentro). A seguradora é chamada uma vez só.
  def call
    conferido = resultado
    return tentativa_sem_gravar(conferido) unless conferido[:estado] == 'ok'

    gravar_aceito!(conferido)
  end

  private

  # Dois pedidos ao mesmo tempo no primeiro cadastro do agente: o segundo INSERT bate no índice único (ou, se o outro já
  # gravou antes da validação, na de unicidade do model); relê a linha que o outro gravou e grava por cima (o último a
  # conferir vale), sem 500.
  def gravar_aceito!(conferido)
    gravar!(conferido)
  rescue ActiveRecord::RecordNotUnique
    gravar!(conferido)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:autonomia_agent_id, :taken)

    gravar!(conferido)
  end

  def tentativa_sem_gravar(conferido)
    Autonomia::Agents::AcessoDaSeguradora.new(account_id: @agent.account_id, autonomia_agent_id: @agent.id, **conferido)
  end

  def gravar!(conferido)
    acesso = Autonomia::Agents::AcessoDaSeguradora.find_or_initialize_by(autonomia_agent_id: @agent.id)
    acesso.account_id = @agent.account_id
    acesso.login = @login
    acesso.senha = @senha
    acesso.assign_attributes(conferido)
    acesso.save!
    acesso
  end

  def resultado
    setup = Autonomia::Seguradoras::Universal::Cliente.new(login: @login, senha: @senha).setup
    { estado: 'ok', motivo: nil, conferido_em: Time.current, capacidades: capacidades_de(setup) }
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
    { estado: ESTADO_POR_CODIGO.fetch(e.codigo, ESTADO_PADRAO), motivo: e.codigo, conferido_em: Time.current, capacidades: {} }
  end

  def capacidades_de(setup)
    campos = setup.is_a?(Hash) ? setup : {}
    CAPACIDADES.to_h { |deles, nossa| [nossa, campos[deles] == true] }
  end
end
