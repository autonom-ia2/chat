# "Trazer" da conferência de "Trazer minha lista" (#2896). Sob a trava da importação, a requisição só confere e põe o
# fechamento na fila: a importação fica `confirmed` e o job (ContactImports::Trazer::FecharConferenciaJob) fecha a
# conferência e manda gravar. Nada do arquivo conferido é aberto aqui. O segundo clique acha a lista já trazida e não
# enfileira de novo.
#
# Também é o "Tentar de novo" da lista cujo fechamento quebrou vezes demais (ContactImports::Trazer::Fechamentos): a
# contagem recomeça e o fechamento volta para a fila.
#
# A rota antiga de "Importar" (POST contact_imports/:id/confirm) passa por aqui sempre que a importação tem a marca:
# ela nunca pula o fechamento da conferência. A rota decide pela marca, que não muda, e não pelo estado que leu antes
# da trava; o estado é conferido aqui, sob a trava (`fecha?`). Só a gravação que parou no meio (`import_resumable?`)
# continua pelo caminho antigo: a conferência dela já foi fechada.
#
# A conferência vencida (ContactImports::Trazer::Conferencia.vencida?) é recusada com `conferencia_vencida`: os
# consertos já sumiram, e a lista entraria sem eles. `nada_para_trazer` fica como defesa para o arquivo conferido que
# sumiu antes da hora.
class Relacionamentos::Trazer::Trazer
  VENCIDA = ContactImports::Trazer::Conferencia::VENCIDA
  Resultado = Struct.new(:erro, keyword_init: true) do
    # A rota antiga de confirmar só conhece "não está pronta"; a conferência vencida ela diz com o código da tela nova.
    def erro_da_rota_antiga
      erro == VENCIDA ? erro : 'campaign_import.not_ready'
    end
  end
  JA_TRAZIDA = (Relacionamentos::Trazer::Situacao::TRAZENDO + Relacionamentos::Trazer::Situacao::GRAVADA).freeze

  # A importação marcada que este "Trazer" confirma: a leitura pronta ou a lista cujo fechamento desistiu.
  def self.fecha?(importacao)
    return false unless ContactImports::Trazer::Conferencia.marcada?(importacao)

    importacao.ready_to_confirm? || ContactImports::Trazer::Fechamentos.desistiu?(importacao)
  end

  def initialize(importacao)
    @importacao = importacao
  end

  def call
    @importacao.with_lock do
      next Resultado.new if JA_TRAZIDA.include?(@importacao.status)
      next Resultado.new(erro: VENCIDA) if ContactImports::Trazer::Conferencia.vencida?(@importacao)
      next Resultado.new(erro: 'leitura_nao_pronta') unless self.class.fecha?(@importacao)
      next Resultado.new(erro: 'nada_para_trazer') unless quantas_entram.positive?

      confirmar
      ContactImports::Trazer::FecharConferenciaJob.perform_later(@importacao)
      Resultado.new
    end
  end

  private

  def confirmar
    ContactImports::Trazer::Fechamentos.new(@importacao).recomecar
    ContactImports::Trazer::Conferencia.new(@importacao).tirar(ContactImports::Trazer::DesfazerMudanca::AVISO)
    @importacao.update!(status: :confirmed, confirmed_at: Time.current)
  end

  # Quem entra é sempre a mesma conta (ContactImports::Trazer::QuemEntra): a que a tela mostrou.
  def quantas_entram
    ContactImports::Trazer::QuemEntra.new(@importacao, ContactImports::Trazer::Consertos.new(@importacao).ler).quantas
  end
end
