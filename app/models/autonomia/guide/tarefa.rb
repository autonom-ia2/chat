# Uma tarefa longa do Guia (#936): um pedido que toca centenas de registros.
#
# O turno do Guia tem 10 idas ao modelo e 180 s de ferramenta; "arruma os 512
# contatos" não cabe. Então o modelo escreve uma RECEITA (`Tarefas::Receita`) e
# uma máquina a aplica item a item (`Tarefas::Lote`, `TarefaJob`), em lotes de
# 25. Cada lote é uma `Execucao` do diário, com o desfazer de 5 dias.
#
# Quem autoriza é a pessoa, sempre: `comecar` e `seguir` só pela tela (estão em
# `Acoes::SEM_DESFAZER`). Depois do primeiro lote a tarefa para sozinha
# (`aguardando_ok_canario`) e mostra o que mudou, para a pessoa conferir.
#
# `receita_digest` é gravado no OK: se a receita mudar depois, o próximo lote
# não roda.
class Autonomia::Guide::Tarefa < ApplicationRecord
  self.table_name = 'autonomia_guide_tasks'

  PRAZO = 5.days
  MAX_ITENS = 5_000

  AMOSTRA_PRONTA = 'amostra_pronta'.freeze
  NA_FILA = 'na_fila'.freeze
  RODANDO = 'rodando'.freeze
  CANARIO = 'aguardando_ok_canario'.freeze
  PAUSADA = 'pausada'.freeze
  CONCLUIDA = 'concluida'.freeze
  CANCELADA = 'cancelada'.freeze
  FALHOU = 'falhou'.freeze
  DESFAZENDO = 'desfazendo'.freeze
  DESFEITA = 'desfeita'.freeze
  STATUS = [AMOSTRA_PRONTA, NA_FILA, RODANDO, CANARIO, PAUSADA, CONCLUIDA, CANCELADA, FALHOU, DESFAZENDO, DESFEITA].freeze
  ANDANDO = [NA_FILA, RODANDO].freeze

  # O comando da pessoa (ou do Guia, nos que têm volta) e de onde ele pode sair.
  TRANSICOES = {
    'comecar' => [[AMOSTRA_PRONTA], NA_FILA],
    'seguir' => [[CANARIO], NA_FILA],
    'pausar' => [ANDANDO, PAUSADA],
    'retomar' => [[PAUSADA], NA_FILA],
    'cancelar' => [[AMOSTRA_PRONTA, NA_FILA, RODANDO, PAUSADA, CANARIO], CANCELADA],
    'desfazer' => [[CANARIO, PAUSADA, CONCLUIDA, CANCELADA, FALHOU], DESFAZENDO]
  }.freeze

  belongs_to :account
  belongs_to :user
  belongs_to :turno, class_name: 'Autonomia::Guide::Turno', optional: true
  has_many :itens, class_name: 'Autonomia::Guide::TarefaItem', foreign_key: :task_id, inverse_of: :tarefa,
                   dependent: :delete_all
  has_many :execucoes, class_name: 'Autonomia::Guide::Execucao', foreign_key: :task_id, inverse_of: :tarefa,
                       dependent: :nullify

  validates :status, inclusion: { in: STATUS }
  validates :descricao, presence: true

  scope :de, ->(account, user) { where(account: account, user: user) }

  before_validation { self.expira_em ||= PRAZO.from_now }

  # A receita como o banco a devolve: o jsonb reordena as chaves, então o
  # digest é tirado da forma canônica (chaves em ordem), nunca do texto enviado.
  def self.digest_de(receita)
    Digest::SHA256.hexdigest(JSON.generate(canonica(receita)))
  end

  def self.canonica(valor)
    case valor
    when Hash then valor.to_h { |chave, item| [chave.to_s, canonica(item)] }.sort.to_h
    when Array then valor.map { |item| canonica(item) }
    else valor
    end
  end

  # Muda de estado só se ainda estiver num dos estados de onde o comando sai. Em
  # SQL, de uma vez: o lote e o clique da pessoa podem chegar juntos.
  def mudar!(comando, **extra)
    origens, destino = TRANSICOES.fetch(comando.to_s)
    mudou = self.class.where(id: id, status: origens)
                .update_all(extra.merge(status: destino, updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
    reload
    mudou == 1
  end

  def receita_intacta?
    receita_digest.present? && receita_digest == self.class.digest_de(receita)
  end

  def andando?
    ANDANDO.include?(status)
  end

  # Mensagem que saiu da conta enquanto o lote rodava, e que não foi de uma
  # pessoa: é o sinal de que a receita acordou uma automação que fala com o
  # cliente (TL08). A atividade (etiqueta posta, status mudado) não conta.
  def mensagem_saiu?(desde, ate)
    inicio = [desde, mensagens_conferidas_ate].compact.max
    ::Message.where(account_id: account_id, created_at: inicio..ate, message_type: %i[outgoing template])
             .exists?(['sender_type IS NULL OR sender_type <> ?', 'User'])
  end

  def contar!
    contagem = itens.group(:status).count
    update!(feitos: contagem.fetch(::Autonomia::Guide::TarefaItem::FEITO, 0), falhas: contagem.fetch(::Autonomia::Guide::TarefaItem::FALHOU, 0),
            pulados: contagem.fetch(::Autonomia::Guide::TarefaItem::PULADO, 0))
  end

  def desfazivel?
    TRANSICOES['desfazer'].first.include?(status) && execucoes_vigentes.any?
  end

  # Até quando dá para desfazer tudo: o prazo do lote mais antigo.
  def desfazer_ate
    execucoes_vigentes.minimum(:expira_em)
  end

  def para_tela
    { 'id' => id, 'status' => status, 'descricao' => descricao, 'total' => total, 'feitos' => feitos,
      'falhas' => falhas, 'pulados' => pulados, 'lotes' => lotes, 'amostra' => amostra, 'canario' => canario,
      'motivo_pausa' => motivo_pausa, 'motivo' => motivo_legivel, 'nao_feitos' => nao_feitos,
      'desfazer' => relatorio['desfazer'], 'desfazivel' => desfazivel?, 'desfazer_ate' => desfazer_ate&.iso8601,
      'criada_em' => created_at.iso8601 }.merge(estimativas)
  end

  # O que vai para a lista "Feito pelo Guia" (#855): a tarefa numa linha só, com os totais.
  def resumo_feito
    { 'id' => "tarefa-#{id}", 'tarefa_id' => id, 'tarefa' => para_tela, 'criada_em' => created_at.iso8601 }
  end

  private

  def estimativas
    { 'custo_estimado' => custo_estimado.to_f, 'custo' => custo.to_f, 'teto_custo' => teto_custo.to_f,
      'jev_estimado' => jev_estimado, 'jev_restante' => relatorio['jev_restante'], 'tempo_estimado' => tempo_estimado }
  end

  def execucoes_vigentes
    execucoes.vigentes.where(desfeita_em: nil)
  end

  def motivo_legivel
    return if motivo_pausa.blank?

    I18n.t("autonomia.guide.tarefa.motivo.#{motivo_pausa}", default: motivo_pausa)
  end

  # Os que não foram feitos, agrupados pelo motivo: o relatório final mostra
  # "12 pulados: já estava certo", e não 12 linhas iguais.
  def nao_feitos
    itens.where(status: [::Autonomia::Guide::TarefaItem::FALHOU, ::Autonomia::Guide::TarefaItem::PULADO]).group(:status, :erro).count
         .map { |(status, erro), quantos| { 'status' => status, 'motivo' => erro, 'total' => quantos } }
         .sort_by { |linha| -linha['total'] }
  end
end
