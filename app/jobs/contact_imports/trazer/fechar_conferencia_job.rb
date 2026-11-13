# "Trazer minha lista" (#2896): o que acontece depois do clique em "Trazer". A requisição só confere e deixa a importação
# `confirmed`; este job fecha a conferência (ContactImports::Trazer::FecharConferencia) e passa a lista para a gravação
# de sempre (CampaignImports::ImportJob). O fechamento é feito sob a trava da importação; os arquivos que ele lê são
# baixados antes dela, para a trava não esperar o armazenamento.
#
# Repetir o job não faz nada: só a importação `confirmed` é fechada, e ela deixa de ser `confirmed` na mesma transação
# em que o fechamento é gravado. O importador não começa uma importação `confirmed`, então a gravação nunca passa na
# frente do fechamento.
#
# A gravação só vai para a fila depois que a transação termina: o arquivo conferido que o fechamento regravou só é
# enviado ao armazenamento quando ela termina, e o importador que começasse antes não o acharia. Se o processo morrer
# entre uma coisa e outra, a importação fica `queued` sem job e a varredura (CampaignImports::StalledImportsJob) a pega.
#
# As tentativas são contadas (ContactImports::Trazer::Fechamentos): o fechamento que quebra sempre não fica em laço. O
# erro continua subindo, para a fila registrar e repetir; na última tentativa a importação vira `failed` com um código.
#
# Sem o arquivo conferido não há o que fechar, e repetir não o traz de volta: o anexo que foi apagado antes do job, ou o
# arquivo (o conferido ou o dos consertos) que não está no armazenamento. A lista vira `failed` com o mesmo código na
# primeira tentativa, em vez de seguir para a gravação ou ficar esperando. O mesmo quando a importação de planilhas está
# desligada na instalação (CAMPAIGN_IMPORT_ENABLED): sem isso a lista ficaria `confirmed` e a tela, "trazendo" sem fim.
class ContactImports::Trazer::FecharConferenciaJob < ApplicationJob
  queue_as :low

  def perform(importacao)
    tentativas = ContactImports::Trazer::Fechamentos.new(importacao)
    return tentativas.desligada unless CampaignImports::Config.enabled?
    return unless tentativas.comecar

    fechada = false
    terminou = false
    begin
      fechada = fechar(importacao, tentativas)
      terminou = true
    rescue ActiveStorage::FileNotFoundError
      terminou = tentativas.sem_arquivo
    ensure
      tentativas.nao_terminou unless terminou
    end
    CampaignImports::ImportJob.perform_later(importacao) if fechada
  end

  private

  # Devolve se fechou: outro job pode ter fechado a mesma importação entre a contagem e a trava.
  def fechar(importacao, tentativas)
    fechamento = ContactImports::Trazer::FecharConferencia.new(importacao).preparar
    importacao.with_lock do
      next false unless importacao.confirmed?

      unless fechamento.call
        tentativas.sem_arquivo
        next false
      end
      tentativas.terminou
      importacao.update!(status: :queued, queued_at: Time.current)
      true
    end
  end
end
