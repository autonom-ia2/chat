# Um pedido ao Guia dentro de uma conversa (#861): a pergunta, a resposta e o
# que ele fez para chegar nela.
#
# `pedido_id` é o mesmo id do `Pedido` no Redis. A tela continua buscando a
# resposta por lá enquanto ela não chega; aqui fica o que sobra depois, para a
# tela reabrir a conversa e para o time investigar um relato (`Investigacao`).
#
# `diagnostico` é o que o Guia leu, chamou e decidiu — só metadado. Nunca entra
# instrução, catálogo, trecho da base, conteúdo do que foi lido nem valor que a
# pessoa mandou gravar (`Registro`).
class Autonomia::Guide::Turno < ApplicationRecord
  self.table_name = 'autonomia_guide_turns'

  PENDENTE = 'pending'.freeze
  PRONTO = 'done'.freeze
  FALHOU = 'failed'.freeze
  RETIDO = 'retido'.freeze
  STATUS = [PENDENTE, PRONTO, FALHOU, RETIDO].freeze

  # Os estados de uma ação sem desfazer, os mesmos da tela.
  ACAO_FEITA = 'feita'.freeze
  ACAO_FALHOU = 'falhou'.freeze

  belongs_to :conversa, class_name: 'Autonomia::Guide::Conversa', foreign_key: :conversation_id,
                        inverse_of: :turnos, touch: true
  belongs_to :execucao, class_name: 'Autonomia::Guide::Execucao', foreign_key: :execution_id, optional: true,
                        inverse_of: false

  validates :pedido_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUS }

  scope :de, ->(account, user) { where(account_id: account.id, user_id: user.id) }

  # Os anexos que a tela mostrou no balão: só nome e tipo. O arquivo em si é
  # apagado em 1 dia (`LimparArquivosJob`), e o áudio da voz nunca é guardado.
  TIPOS_DE_ANEXO = %w[documento imagem].freeze
  MAX_NOME_DE_ANEXO = 255

  class << self
    # O aviso do Guia (#935) entra na conversa como um turno sem pergunta: o Guia falou primeiro.
    def do_aviso(conversa, aviso)
      create!(conversa: conversa, account_id: conversa.account_id, user_id: conversa.user_id, pedido_id: SecureRandom.uuid,
              pergunta: '', status: PRONTO, resposta: aviso.texto, diagnostico: { 'aviso_id' => aviso.id })
    end

    def abrir(conversa:, pedido_id:, pergunta:, tela:, anexos: [])
      create!(conversa: conversa, account_id: conversa.account_id, user_id: conversa.user_id, pedido_id: pedido_id,
              pergunta: pergunta.to_s, tela: tela.to_s.presence, anexos: limpar_anexos(anexos))
    end

    # O desfecho do pedido, com o diagnóstico. Best-effort: a resposta já foi
    # entregue pelo `Pedido`, e uma falha aqui não pode apagá-la.
    def concluir(pedido_id, resultado, diagnostico)
      turno = find_by(pedido_id: pedido_id)
      turno&.update!(desfecho(resultado.to_h.with_indifferent_access).merge(diagnostico: diagnostico))
    rescue StandardError => e
      Rails.logger.warn("[autonomia][guide][turno] concluir pedido=#{pedido_id} #{e.class}")
    end

    def falhar(pedido_id, diagnostico)
      find_by(pedido_id: pedido_id)&.update!(status: FALHOU, diagnostico: diagnostico)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][guide][turno] falhar pedido=#{pedido_id} #{e.class}")
    end

    private

    def desfecho(resultado)
      execucao = resultado[:execucao].to_h.with_indifferent_access
      { status: status_de(resultado), resposta: resultado[:text], navegacoes: Array(resultado[:navigations]),
        artigos: Array(resultado[:artigos]), acao: resultado[:acao], execution_id: execucao[:id],
        passos: Array(execucao[:passos]) }
    end

    def status_de(resultado)
      return RETIDO if resultado[:retido]
      return FALHOU unless resultado[:available]

      PRONTO
    end

    def limpar_anexos(anexos)
      Array(anexos).first(::Autonomia::Guide::Arquivos::MAX_POR_TURNO).filter_map do |anexo|
        next unless anexo.respond_to?(:to_h) || anexo.respond_to?(:to_unsafe_h)

        dados = (anexo.respond_to?(:to_unsafe_h) ? anexo.to_unsafe_h : anexo.to_h).with_indifferent_access
        nome = dados[:nome].to_s.first(MAX_NOME_DE_ANEXO)
        next if nome.blank?

        { 'nome' => nome, 'tipo' => TIPOS_DE_ANEXO.include?(dados[:tipo].to_s) ? dados[:tipo].to_s : TIPOS_DE_ANEXO.first }
      end
    end
  end

  # A ida e a volta deste turno, no formato do histórico do Guia. O aviso (#935) não tem pergunta, e o
  # Guia lê o número dele para achar o sinal em `autonomia/avisos`.
  def mensagens
    return [{ role: 'assistant', content: "#{resposta}\n(aviso #{aviso_id})" }] if aviso_id

    [{ role: 'user', content: pergunta }, ({ role: 'assistant', content: resposta } if resposta.present?)].compact
  end

  def aviso_id
    diagnostico.is_a?(Hash) ? diagnostico['aviso_id'] : nil
  end

  def para_tela
    { 'pedido_id' => pedido_id, 'pergunta' => pergunta, 'anexos' => anexos, 'status' => status,
      'resposta' => resposta, 'navegacoes' => navegacoes, 'artigos' => artigos, 'acao' => acao,
      'acao_estado' => acao_estado, 'acao_resultado' => acao_resultado, 'execucao' => execucao_para_tela,
      'aviso_id' => aviso_id, 'tarefa' => tarefa_para_tela, 'criado_em' => created_at.iso8601 }
  end

  # #936 — a tarefa longa planejada neste turno: o cartão volta ao reabrir a conversa e busca o
  # andamento em `GET tarefas/:id`.
  def tarefa_para_tela
    tarefa = ::Autonomia::Guide::Tarefa.where(turno_id: id).order(:id).last
    tarefa && { 'id' => tarefa.id, 'status' => tarefa.status }
  end

  # O desfazer vale 5 dias; a conversa fica guardada sem prazo. Enquanto a
  # execução existe, a tela recebe o resumo ao vivo (com o botão de desfazer).
  # Depois, só o que foi feito.
  def execucao_para_tela
    return execucao.resumo if execucao.present?
    return nil if passos.blank?

    { 'passos' => passos, 'vencida' => true }
  end
end
