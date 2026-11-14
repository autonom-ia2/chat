# "Trazer minha lista" (#2896): a importação com a marca options['trazer'] que ficou parada porque um job se perdeu (o
# worker morreu, o deploy caiu no meio). A varredura de Campanhas (CampaignImports::StalledImportsJob) chama esta classe
# a cada passada. Dois casos, os dois medidos contra CampaignImports::Config.stalled_import_after:
#
# - parada em `confirmed`: "Trazer" deixou a importação assim e o ContactImports::Trazer::FecharConferenciaJob se
#   perdeu. Nada mais a tiraria dali e a tela mostraria "trazendo" para sempre. O fechamento volta para a fila;
# - parada em `uploaded` ou `validating`: a leitura da planilha (CampaignImports::ValidateJob) se perdeu, e a tela
#   mostraria "lendo" para sempre. A leitura volta para a fila, no máximo VOLTAS vezes (a contagem fica em
#   options['trazer']['releituras'], só o número, e some quando uma leitura termina). Na volta seguinte a varredura
#   desiste: a importação vira `validation_failed` com `file_could_not_be_processed`, que a tela mostra como "falhou".
#
# A varredura não tira a vez de uma leitura viva. Pôr a leitura de volta na fila faz a leitura nova trocar o número, e
# a que estava rodando é descartada quando termina (ContactImports::Trazer::Validador). Por isso a leitura que COMEÇOU
# (`validating` com o instante do começo em options['trazer']['leitura_em']) tem VIVA prazos, contados desse instante,
# para terminar; só depois disso ela volta para a fila, e a volta é contada. A que nunca começou (`uploaded`, ou
# `validating` sem o instante: a pessoa pediu a leitura e o job se perdeu) volta depois de um prazo.
#
# A importação sem a marca nunca é tocada aqui. A leitura da importação vencida
# (ContactImports::Trazer::Conferencia.vencida?) também não: a tela já a mostra como vencida, e ler a planilha de novo
# não mudaria isso. A lista já mandada trazer (`confirmed`) não vence, e o fechamento dela volta para a fila.
#
# O tempo conta do último movimento da importação (`updated_at`) e é conferido de novo sob a trava, a mesma que os jobs
# tomam. Quem volta para a fila fica marcado como mexido agora: duas varreduras não enfileiram duas vezes, e se o job se
# perder de novo o prazo seguinte a pega outra vez. O job repetido não faz mal: o fechamento só fecha a importação que
# ainda está `confirmed` e conta as tentativas (ContactImports::Trazer::Fechamentos); a leitura repetida lê a planilha
# de novo e chega ao mesmo resultado.
#
# Uma importação que quebra não impede as seguintes. O log leva só o id e a classe do erro: a mensagem pode trazer o
# que a importação guarda.
class ContactImports::Trazer::ConferenciasParadas
  LENDO = %w[uploaded validating].freeze
  PARADAS = (LENDO + %w[confirmed]).freeze
  VOLTAS = 2
  # Quantos prazos a leitura que começou tem para terminar antes de a varredura a dar por perdida.
  VIVA = 3
  NAO_LEU = 'file_could_not_be_processed'.freeze

  def call
    paradas.find_each do |importacao|
      reenfileirar(importacao)
    rescue StandardError => e
      Rails.logger.error("[ContactImports::Trazer::ConferenciasParadas] import_id=#{importacao.id} #{e.class}")
    end
  end

  private

  def paradas
    CampaignImport.where(status: PARADAS).where("options -> 'trazer' IS NOT NULL").where(updated_at: ...limite)
  end

  def limite
    prazo.ago
  end

  def prazo
    CampaignImports::Config.stalled_import_after
  end

  def reenfileirar(importacao)
    job = nil
    importacao.with_lock do
      job = job_de(importacao) if importacao.updated_at < limite && !leitura_viva?(importacao)
      importacao.touch if job # rubocop:disable Rails/SkipsModelValidations -- só a hora do último movimento
    end
    return unless job

    job.perform_later(importacao)
    Rails.logger.warn("[ContactImports::Trazer::ConferenciasParadas] import_id=#{importacao.id} requeued")
  end

  def leitura_viva?(importacao)
    comecou = ContactImports::Trazer::Conferencia.new(importacao).leitura_em
    importacao.validating? && comecou.present? && comecou >= (VIVA * prazo).ago
  end

  # O job que tira a importação do estado em que ela parou, ou nil se ela já saiu dele ou se a varredura desistiu.
  def job_de(importacao)
    return if ContactImports::Trazer::Conferencia.vencida?(importacao)
    return ContactImports::Trazer::FecharConferenciaJob if importacao.confirmed?

    mais_uma_leitura(importacao) if LENDO.include?(importacao.status)
  end

  def mais_uma_leitura(importacao)
    conferencia = ContactImports::Trazer::Conferencia.new(importacao)
    return desistir_da_leitura(importacao, conferencia) if conferencia.releituras >= VOLTAS

    conferencia.gravar('releituras' => conferencia.releituras + 1)
    CampaignImports::ValidateJob
  end

  def desistir_da_leitura(importacao, conferencia)
    conferencia.tirar(*ContactImports::Trazer::Validador::DA_LEITURA)
    importacao.update!(status: :validation_failed, validated_at: Time.current, validation_summary: { 'errors' => { NAO_LEU => 1 } })
    Rails.logger.warn("[ContactImports::Trazer::ConferenciasParadas] import_id=#{importacao.id} reading gave up")
    nil
  end
end
