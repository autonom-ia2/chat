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
#
# Com uma coluna dizendo quem é cliente e sem a pessoa ter escolhido quais valores dela querem dizer cliente, ou com a
# escolha apontando um valor que a coluna não tem mais (Relacionamentos::Trazer::Perguntas#falta_valores_cliente?,
# conferido aqui, sob a trava), a recusa é `falta_valores_cliente`: nunca se traz adivinhando nem com meia escolha.
#
# Enquanto a conta desfaz uma lista (Relacionamentos::Trazer::Desfazer.em_curso?), a recusa é `desfazer_em_curso`: a
# lista nova completaria uma pessoa que o desfazer está apagando. Nada muda na leitura; é só esperar e trazer de novo.
class Relacionamentos::Trazer::Trazer
  VENCIDA = ContactImports::Trazer::Conferencia::VENCIDA
  DESFAZER_EM_CURSO = 'desfazer_em_curso'.freeze
  # As recusas que a rota antiga diz com o código da tela nova: têm frase própria, que diz o que fazer.
  COM_FRASE_PROPRIA = [VENCIDA, DESFAZER_EM_CURSO].freeze
  Resultado = Struct.new(:erro, keyword_init: true) do
    # A rota antiga de confirmar só conhece "não está pronta"; a conferência vencida e o desfazer em curso ela diz com
    # o código da tela nova.
    def erro_da_rota_antiga
      COM_FRASE_PROPRIA.include?(erro) ? erro : 'campaign_import.not_ready'
    end
  end
  JA_TRAZIDA = (Relacionamentos::Trazer::Situacao::TRAZENDO + Relacionamentos::Trazer::Situacao::GRAVADA).freeze
  # O Guia pede confirmação antes de toda escrita da conferência (`Autonomia::Guide::Acoes::SEM_DESFAZER`): o caderno do
  # desfazer dele só enxerga o que passa por callback de model, e aqui se grava com update_all, anexo e job. Enviar a
  # planilha e trazer a lista ainda gravam em lote. O "Desfazer" de uma lista (fatia 3) também: apaga pessoas e esvazia
  # campos em lote, num job, e não tem desfazer do desfazer. Os nomes são os do catálogo do Guia (verbo e rota).
  SEM_DESFAZER_DO_GUIA = [
    'POST relacionamentos/trazer/leituras', 'POST relacionamentos/trazer/leituras/:id/trazer',
    'PATCH relacionamentos/trazer/leituras/:id/respostas',
    'PATCH relacionamentos/trazer/leituras/:leitura_id/colunas/:indice', 'PUT relacionamentos/trazer/leituras/:leitura_id/colunas/:indice',
    'PATCH relacionamentos/trazer/leituras/:leitura_id/linhas/:linha', 'PUT relacionamentos/trazer/leituras/:leitura_id/linhas/:linha',
    'POST relacionamentos/trazer/leituras/:leitura_id/linhas/:linha/deixar_de_fora',
    'POST relacionamentos/trazer/leituras/:leitura_id/linhas/:linha/reabrir',
    'POST relacionamentos/trazer/listas/:id/desfazer'
  ].freeze

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
      next Resultado.new(erro: 'falta_valores_cliente') if Relacionamentos::Trazer::Perguntas.new(@importacao).falta_valores_cliente?
      next Resultado.new(erro: 'nada_para_trazer') unless quantas_entram.positive?
      next Resultado.new(erro: DESFAZER_EM_CURSO) if Relacionamentos::Trazer::Desfazer.em_curso?(@importacao.account)

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
