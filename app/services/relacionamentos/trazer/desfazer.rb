# O "Desfazer" de uma lista trazida (#2896): tira da base o que a lista pôs e em que ninguém tocou.
#
# 0. Na lista que trouxe seguros (E4, #2897), antes de tudo: o seguro que ela criou e em que ninguém mexeu sai da
#    carteira, e o que ela só completou num seguro que já existia volta ao que era (Carteira::Trazer::DesfazerSeguros).
#    O seguro que alguém já corrigiu, que tem PDF, renovação em andamento ou resultado fica, e segura a pessoa dele.
#    Vem primeiro porque os passos seguintes olham a carteira como ela fica: a pessoa sem seguro pode sair, e quem
#    continua com seguro continua cliente.
# 1. A pessoa que a lista criou sai, a menos que já tenha conversa, card, campanha, seguro ou recusa, ou que alguém a
#    tenha editado (Relacionamentos::Trazer::QuemFica). Sai pelo serviço de apagar em lote de hoje
#    (Contacts::BulkDeleteService), com os avisos de sempre: aqui nenhum evento é suprimido. Apagar um bloco leva tempo,
#    e nesse tempo alguém pode cuidar da pessoa: por isso o bloco é conferido de novo de FATIA em FATIA pessoas, por
#    todas as regras de uma vez, e o que chega em segundos (a conversa, o card e a nota) pessoa a pessoa, logo antes
#    de sair. As outras regras só valem até a conferência da fatia: o que mudar nelas depois disso já não segura a
#    pessoa. A pessoa em que o apagar dá errado (a reunião que não cancela, o card que mudou, um erro do banco) fica, e
#    o Desfazer segue com as outras: quantas ficaram assim é contado e guardado na importação (`ficaram`), para a tela
#    dizer.
# 2. Na pessoa que a conta já tinha, cada campo que a lista preencheu volta a vazio, se o valor ainda é o que a lista
#    pôs (Relacionamentos::Trazer::CampoQueVolta). A empresa a que a lista a ligou é desligada, e quem a lista marcou
#    como cliente volta ao tipo que tinha. Essa volta não avisa "contato mudou" (webhooks, automações): são muitas
#    pessoas de uma vez, como na gravação da lista e no desfazer das etiquetas (CampaignImports::SuppressedContactEvents).
# 3. A empresa que a lista criou sai quando não sobra nenhuma pessoa nela, nem retorno marcado para ela (o retorno sairia
#    junto, pela cascata do banco, e foi alguém que o marcou), nem seguro em nome dela (a apólice ficaria sem a empresa).
# 4. As anotações da lista que já não servem saem: as das pessoas que não estão mais na base e as dos campos que
#    voltaram (Relacionamentos::CampoPreenchido). O resumo de um telefone não fica guardado depois que a pessoa saiu.
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
#
# Enquanto um desfazer anda na conta (`em_curso?`), "Trazer" é recusado (Relacionamentos::Trazer::Trazer): a lista nova
# completaria uma pessoa que está de saída.
class Relacionamentos::Trazer::Desfazer
  include CampaignImports::SuppressedContactEvents

  NAO_PODE = 'nao_pode_desfazer'.freeze
  GRAVADA = Relacionamentos::Trazer::Situacao::GRAVADA
  BLOCO = Relacionamentos::Trazer::QuemFica::BLOCO
  # De quantas em quantas pessoas o bloco é conferido de novo antes de apagar.
  FATIA = 50
  # Onde fica, na importação (validation_summary), quantas pessoas deviam sair e ficaram. Só o número.
  FICARAM = 'desfazer_ficaram'.freeze
  Campo = Relacionamentos::CampoPreenchido
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

  # Há um desfazer andando na conta. O que parou no meio não conta: nada está sendo apagado, e ele só volta a andar
  # quando a pessoa clica em "Continuar".
  def self.em_curso?(conta)
    vivos = conta.campaign_imports.contact_imports.undo_status_processing
    vivos.exists?(updated_at: CampaignImports::Config.stalled_import_after.ago..)
  end

  # Quantas pessoas o desfazer desta lista devia tirar e não tirou.
  def self.ficaram(importacao)
    importacao.validation_summary.to_h[FICARAM].to_i
  end

  # quem: a pessoa que pediu. Com a flag `crm_arquivados` ligada na conta, vai para a Auditoria de quem foi apagado; sem
  # a flag, o apagar em lote não registra quem pediu.
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

    Carteira::Trazer::DesfazerSeguros.new(@importacao).call { vivo }
    ficaram = apagar_as_pessoas_criadas
    with_suppressed_contact_events { devolver_os_campos }
    apagar_as_empresas_criadas
    apagar_as_anotacoes
    terminar(ficaram)
  rescue StandardError
    @importacao.update!(undo_status: :failed, undo_finished_at: Time.current)
    raise
  end

  # O clique marcou "desfazendo" e o job não chegou à fila: a marca volta, para a tela oferecer o Desfazer de novo.
  def desistir
    @importacao.with_lock do
      @importacao.update!(undo_status: :failed, undo_finished_at: Time.current) if @importacao.undo_status_processing?
    end
  end

  private

  def terminar(ficaram)
    agora = Time.current
    resumo = @importacao.validation_summary.to_h.except(FICARAM)
    resumo = resumo.merge(FICARAM => ficaram) if ficaram.positive?
    @importacao.update!(undo_status: :completed, undo_finished_at: agora, undo_completed_at: agora, validation_summary: resumo)
  end

  # O desfazer que parou volta para a fila, e a marca de vida é renovada para o próximo clique não enfileirar outro.
  def retomar
    return false unless self.class.parado?(@importacao)

    vivo
    true
  end

  def vivo
    @importacao.touch # rubocop:disable Rails/SkipsModelValidations -- só o carimbo se move
  end

  # Devolve quantas pessoas deviam sair e ficaram.
  def apagar_as_pessoas_criadas
    quem_fica = Relacionamentos::Trazer::QuemFica.new(@importacao)
    ficaram = 0
    quem_fica.em_blocos do |saem, _ficam|
      saem.each_slice(FATIA) do |fatia|
        ficaram += apagar(fatia - quem_fica.entre(fatia).to_a, quem_fica)
        vivo
      end
    end
    ficaram
  end

  # ids: pessoas que acabaram de passar de novo por todas as regras de quem fica. Devolve quantas o apagar em lote manteve.
  def apagar(ids, quem_fica)
    tentadas = ids.select { |id| tirar(id, quem_fica) }
    tentadas.empty? ? 0 : @conta.contacts.where(id: tentadas).count
  end

  # Diz se tentou tirar a pessoa: quem ganhou conversa, card ou nota agora há pouco fica, e não conta como falha.
  def tirar(id, quem_fica)
    return false if quem_fica.tem_conversa_card_ou_nota?(id)

    apagar_uma(id)
    true
  end

  # Sem a flag `crm_arquivados`, o apagar em lote deixa o erro de uma pessoa subir. Aqui ele não derruba o Desfazer: a
  # pessoa fica, entra na conta das que ficaram (`apagar` conta quem foi tentada e ainda existe) e as outras seguem. O
  # registro leva só o id da pessoa e a classe do erro, nunca a mensagem: a mensagem de erro do banco traz valor.
  def apagar_uma(id)
    Contacts::BulkDeleteService.new(account: @conta, contact_ids: [id], user: @quem).perform
  rescue StandardError => e
    Rails.logger.warn("[relacionamentos][trazer][desfazer] contact=#{id} kept: #{e.class.name}")
  end

  def devolver_os_campos
    Relacionamentos::Trazer::CamposDaLista.new(@importacao).em_blocos do |campos|
      campos.group_by(&:alvo).each_value { |do_alvo| Relacionamentos::Trazer::CampoQueVolta.devolver!(do_alvo) }
      vivo
    end
  end

  # Sob a trava da empresa: quem foi ligado a ela enquanto o desfazer rodava a mantém. A lista sem anotação nenhuma (a
  # da tela antiga, que nunca anota) não apaga empresa: dela o Desfazer não tira nada.
  def apagar_as_empresas_criadas
    return unless Campo.da_importacao(@importacao).exists?

    criadas = @importacao.campaign_import_rows.where(company_result: CRIADA).where.not(company_id: nil).distinct.pluck(:company_id)
    criadas.each_slice(BLOCO) do |ids|
      @conta.companies.where(id: ids).where.missing(:contacts).find_each do |empresa|
        empresa.with_lock { empresa.destroy! unless em_uso?(empresa) }
      end
      vivo
    end
  end

  def em_uso?(empresa)
    empresa.contacts.exists? || Crm::FollowUp.exists?(company_id: empresa.id) || Crm::FollowUpSeries.exists?(company_id: empresa.id) ||
      Carteira::Apolice.exists?(company_id: empresa.id)
  end

  # Saem as anotações das pessoas que não estão mais na base (as que o desfazer tirou e as apagadas à mão) e as dos
  # campos que voltaram. Ficam as do que não voltou em quem continua aqui.
  def apagar_as_anotacoes
    da_lista = Campo.da_importacao(@importacao)
    sem_uso = da_lista.where.not(devolvido_em: nil).or(da_lista.where.not(contact_id: @conta.contacts.select(:id)))
    sem_uso.in_batches(of: BLOCO).delete_all
    vivo
  end
end
