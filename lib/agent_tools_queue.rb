# #1430 — a FILA PRÓPRIA das ferramentas HTTP que rodam assíncronas (`Autonomia::Agents::Tools::HttpAssincronaJob`).
#
# Uma chamada pode esperar o tempo inteiro da ferramenta (sem máximo, decisão do Rodrigo de 31/10). Na fila comum, uma
# conta com o sistema lento ocuparia as threads de todas as filas. Aqui ela roda num capsule do Sidekiq 7.3, com
# threads só dela: o isolamento é ENTRE FILAS (as consultas não tomam as threads do resto do produto). A EQUIDADE ENTRE
# CONTAS dentro do capsule é outra regra, do job (`HttpAssincronaJob#ceder_a_vez?`): a conta que já ocupa mais da metade
# das threads cede a vez quando outra espera. Proteção contra defeito, não teto de uso (aprovado pelo Rodrigo).
#
# A fila NÃO entra no `config/sidekiq.yml`: se entrasse, as threads do processo principal também a pegariam, e o
# isolamento acabava.
#
# O pool do banco do worker é a soma das threads do processo principal e das do capsule (`pool_do_sidekiq`, lido pelo
# `config/database.yml`). O capsule e o pool leem o mesmo ENV, com o mesmo padrão, por este módulo; as do processo
# principal saem da configuração que o Sidekiq já montou do `config/sidekiq.yml` (lido antes de o Rails subir): cada
# número tem uma fonte só. Em produção (31/10/2026), um worker por stack: Hub2You com SIDEKIQ_CONCURRENCY=30 e
# max_connections 181; Autonom.ia com o padrão 10 e max_connections 79. Os +10 cabem nas duas.
#
# Carregado à mão pelo `database.yml` (antes do autoload), por isso só Ruby puro aqui; o `Sidekiq`, que o database.yml
# já usa, é lido na hora da chamada.
module AgentToolsQueue
  FILA = 'agent_tools'.freeze
  CONCORRENCIA_PADRAO = 10

  module_function

  def concorrencia
    inteiro('AGENT_TOOLS_CONCURRENCY', CONCORRENCIA_PADRAO)
  end

  # `principal`: as threads do processo principal, as do capsule padrão que o Sidekiq montou do `config/sidekiq.yml`.
  def pool_do_sidekiq(principal = Sidekiq.default_configuration.concurrency)
    principal + concorrencia
  end

  # ENV que não é inteiro positivo não derruba o boot (o database.yml lê isto antes de tudo): cai no padrão e avisa no
  # stderr, que é o que existe antes do logger.
  def inteiro(nome, padrao)
    valor = Integer(ENV.fetch(nome, padrao).to_s, 10, exception: false)
    return valor if valor&.positive?

    warn("[agent_tools_queue] #{nome}=#{ENV.fetch(nome, nil).inspect} não é inteiro positivo; usando #{padrao}")
    padrao
  end

  # Chamado pelo `Sidekiq.configure_server` do initializer.
  def configurar(config)
    config.capsule(FILA) do |capsule|
      capsule.concurrency = concorrencia
      capsule.queues = [FILA]
    end
  end
end
