# O "Desfazer" de uma lista trazida (#2896): tira da base o que a lista pôs e em que ninguém tocou.
#
# 1. A pessoa que a lista criou sai, a menos que já tenha conversa, card, campanha ou recusa
#    (Relacionamentos::Trazer::QuemFica). Sai pelo serviço de apagar em lote de hoje (Contacts::BulkDeleteService),
#    com os avisos de sempre: nenhum evento é suprimido. Apagar um bloco leva tempo, e nesse tempo chega mensagem: por
#    isso cada pessoa é conferida de novo logo antes de sair.
# 2. Na pessoa que a conta já tinha, cada campo que a lista preencheu volta a vazio, se o valor ainda é o que a lista
#    pôs (Relacionamentos::Trazer::CampoQueVolta). A empresa a que a lista a ligou é desligada, e quem a lista marcou
#    como cliente volta ao tipo que tinha.
# 3. A empresa que a lista criou sai quando não sobra nenhuma pessoa nela nem retorno marcado para ela (o retorno sairia
#    junto, pela cascata do banco, e foi alguém que o marcou).
#
# `pedir` é o clique: sob a trava da importação, marca "desfazendo" e diz se o job deve ir para a fila. Pode ser desfeita
# a lista gravada e a que quebrou no meio da gravação: as pessoas que ela chegou a pôr não podem ficar presas numa lista
# que não dá para apagar nem para continuar. O segundo clique não enfileira de novo, a não ser que o desfazer esteja parado há mais
# tempo que CampaignImports::Config.stalled_import_after (o processo morreu no meio): aí o job volta para a fila.
#
# `call` é o job, em blocos de QuemFica::BLOCO. Cada bloco move o `updated_at` da importação, que é por onde se vê que o
# desfazer está vivo. Rodar de novo não repete nada: quem já saiu não existe mais e o campo devolvido fica marcado
# (`devolvido_em`). Só o estado do desfazer é gravado na importação (`undo_status` e os três carimbos); as linhas dela
# não são tocadas. Se quebrar, o desfazer fica `failed` (a tela volta a mostrar "pronto" e a pessoa pode pedir de novo)
# e o erro sobe para a fila registrar.
class Relacionamentos::Trazer::Desfazer
  NAO_PODE = 'nao_pode_desfazer'.freeze
  GRAVADA = Relacionamentos::Trazer::Situacao::GRAVADA
  BLOCO = Relacionamentos::Trazer::QuemFica::BLOCO
  # O que o vinculador de empresas grava na linha quando a empresa nasceu com ela (CampaignImports::CompanyLinker).
  CRIADA = 'created'.freeze
  Pedido = Struct.new(:erro, :enfileirar, keyword_init: true)

  def self.pode?(importacao)
    GRAVADA.include?(importacao.status) || (importacao.failed? && importacao.import_started_at.present?)
  end

  # O desfazer parou: nada mexe na importação há mais tempo que o limite (o processo morreu no meio). A tela volta a
  # oferecer o Desfazer nessa lista, e o clique o põe na fila de novo.
  def self.parado?(importacao)
    importacao.undo_status_processing? && importacao.updated_at < CampaignImports::Config.stalled_import_after.ago
  end

  # quem: a pessoa que pediu. Vai para a Auditoria de quem foi apagado.
  def initialize(importacao, quem: nil)
    @importacao = importacao
    @conta = importacao.account
    @quem = quem
  end

  def pedir
    @importacao.with_lock do
      next Pedido.new(erro: NAO_PODE) unless self.class.pode?(@importacao)
      next Pedido.new(enfileirar: false) if @importacao.undo_status_completed?
      next Pedido.new(enfileirar: retomar) if @importacao.undo_status_processing?

      @importacao.update!(undo_status: :processing, undo_started_at: Time.current, undo_finished_at: nil)
      Pedido.new(enfileirar: true)
    end
  end

  def call
    return unless self.class.pode?(@importacao) && @importacao.undo_status_processing?

    apagar_as_pessoas_criadas
    devolver_os_campos
    apagar_as_empresas_criadas
    agora = Time.current
    @importacao.update!(undo_status: :completed, undo_finished_at: agora, undo_completed_at: agora)
  rescue StandardError
    @importacao.update!(undo_status: :failed, undo_finished_at: Time.current)
    raise
  end

  private

  # O desfazer que parou volta para a fila, e a marca de vida é renovada para o próximo clique não enfileirar outro.
  def retomar
    return false unless self.class.parado?(@importacao)

    vivo
    true
  end

  def vivo
    @importacao.touch # rubocop:disable Rails/SkipsModelValidations -- só o carimbo se move
  end

  def apagar_as_pessoas_criadas
    quem_fica = Relacionamentos::Trazer::QuemFica.new(@importacao)
    quem_fica.em_blocos do |saem, _ficam|
      saem.each do |id|
        Contacts::BulkDeleteService.new(account: @conta, contact_ids: [id], user: @quem).perform unless quem_fica.fica?(id)
      end
      vivo
    end
  end

  def devolver_os_campos
    Relacionamentos::Trazer::CamposDaLista.new(@importacao).em_blocos do |campos|
      campos.group_by(&:alvo).each_value { |do_alvo| Relacionamentos::Trazer::CampoQueVolta.devolver!(do_alvo) }
      vivo
    end
  end

  # Sob a trava da empresa: quem foi ligado a ela enquanto o desfazer rodava a mantém.
  def apagar_as_empresas_criadas
    criadas = @importacao.campaign_import_rows.where(company_result: CRIADA).where.not(company_id: nil).distinct.pluck(:company_id)
    criadas.each_slice(BLOCO) do |ids|
      @conta.companies.where(id: ids).where.missing(:contacts).find_each do |empresa|
        empresa.with_lock { empresa.destroy! unless em_uso?(empresa) }
      end
      vivo
    end
  end

  def em_uso?(empresa)
    empresa.contacts.exists? || Crm::FollowUp.exists?(company_id: empresa.id) || Crm::FollowUpSeries.exists?(company_id: empresa.id)
  end
end
