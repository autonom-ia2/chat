# #1430 — a FILA PRÓPRIA das ferramentas HTTP que rodam assíncronas (`Autonomia::Agents::Tools::HttpAssincronaJob`).
#
# Uma chamada pode esperar o tempo inteiro da ferramenta (sem máximo, decisão do Rodrigo de 31/10). Na fila comum, uma
# conta com o sistema lento ocuparia as threads de todas as contas. Aqui ela roda num capsule do Sidekiq 7.3, com
# threads só dela: é isolamento entre contas e proteção contra defeito, não teto de uso (aprovado pelo Rodrigo).
#
# A fila NÃO entra no `config/sidekiq.yml`: se entrasse, as threads do processo principal também a pegariam, e o
# isolamento acabava.
#
# O pool do banco do worker é a soma das threads do processo principal e das do capsule (`pool_do_sidekiq`, lido pelo
# `config/database.yml`). O capsule e o pool leem o mesmo ENV, com o mesmo padrão, por este módulo: os dois nunca
# divergem. Em produção (31/10/2026), um worker por stack: Hub2You com SIDEKIQ_CONCURRENCY=30 e max_connections 181;
# Autonom.ia com o padrão 10 e max_connections 79. Os +10 cabem nas duas.
#
# Carregado à mão pelo `database.yml` (antes do autoload), por isso só Ruby puro aqui.
module AgentToolsQueue
  FILA = 'agent_tools'.freeze
  CONCORRENCIA_PADRAO = 10
  # O padrão do `config/sidekiq.yml` (`:concurrency:`), para a soma do pool.
  CONCORRENCIA_PRINCIPAL_PADRAO = 10

  module_function

  def concorrencia
    inteiro('AGENT_TOOLS_CONCURRENCY', CONCORRENCIA_PADRAO)
  end

  def pool_do_sidekiq
    inteiro('SIDEKIQ_CONCURRENCY', CONCORRENCIA_PRINCIPAL_PADRAO) + concorrencia
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
