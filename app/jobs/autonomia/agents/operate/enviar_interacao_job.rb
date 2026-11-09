# A ÂNCORA QUE GRAVOU A INTERAÇÃO DEPOIS DO ÁUDIO (#1479) vai por esta classe, e não pela `EnviarCartoesJob`: o mesmo
# trabalho, com outro nome na fila. No deploy, o worker que ainda roda a versão sem a interação não conhece esta classe:
# o job falha ao carregar, o Sidekiq o refaz mais tarde, e quem o pega é o worker novo. Pela `EnviarCartoesJob`, o
# worker antigo veria a âncora sem cartão e sairia sem postar, e a pergunta se perderia calada.
# As tentativas vão no próprio job (o worker antigo as respeita): com o `max_retries: 3` da instalação, a janela seria
# de ~1 min e a sobreposição das duas stacks no deploy pode passar disso. 6 tentativas cobrem ~18 min. No rollback a
# classe deixa de existir: o job na fila esgota as tentativas e vai para os mortos (a pergunta não sai).
# O reagendamento (`self.class.set`) continua nesta classe.
class Autonomia::Agents::Operate::EnviarInteracaoJob < Autonomia::Agents::Operate::EnviarCartoesJob
  sidekiq_options retry: 6
end
