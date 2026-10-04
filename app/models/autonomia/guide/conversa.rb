# Uma conversa de uma pessoa com o Guia, numa conta (#861).
#
# Antes ela vivia só na memória do navegador: recarregar a página apagava tudo,
# e o Guia esquecia o assunto. Agora a tela reabre a conversa atual e lista as
# anteriores, e o histórico que o Guia lê sai daqui, montado no servidor.
#
# É de QUEM perguntou: as respostas saíram com a permissão dela, e outra pessoa
# da mesma conta não lê — nem sabe que a conversa existe (404, como `Pedido`).
#
# Fica guardada sem prazo: não há limpeza automática (decisão do Rodrigo,
# 03/10/2026). Só sai quando a pessoa apaga, pelo histórico do painel.
class Autonomia::Guide::Conversa < ApplicationRecord
  self.table_name = 'autonomia_guide_conversations'

  TAMANHO_DO_TITULO = 120

  belongs_to :account
  belongs_to :user
  has_many :turnos, -> { order(:created_at, :id) }, class_name: 'Autonomia::Guide::Turno',
                                                    foreign_key: :conversation_id, inverse_of: :conversa,
                                                    dependent: :delete_all

  scope :de, ->(account, user) { where(account: account, user: user) }
  scope :recentes, -> { order(updated_at: :desc, id: :desc) }

  # O título é a primeira pergunta, cortada. Sem IA: custaria uma chamada por
  # conversa para algo que a pessoa reconhece pela própria frase.
  def self.titulo_para(pergunta)
    pergunta.to_s.squish.truncate(TAMANHO_DO_TITULO)
  end

  # O que o Guia lê como conversa: as idas e voltas até aqui, na ordem em que
  # aconteceram. Só entra resposta de verdade — o aviso de "não consegui" que a
  # tela mostra não é fala do Guia.
  def historico(limite: ::Autonomia::Guide::Chat::MAX_HISTORY)
    recentes = turnos.reorder(created_at: :desc, id: :desc).limit(limite).select(:id, :pergunta, :resposta, :diagnostico)
    recentes.reverse.flat_map(&:mensagens).last(limite)
  end

  def resumo
    { 'id' => id, 'titulo' => titulo, 'atualizada_em' => updated_at.iso8601 }
  end

  def para_tela
    { 'id' => id, 'titulo' => titulo, 'atualizada_em' => updated_at.iso8601,
      'turnos' => turnos.includes(:execucao).map(&:para_tela) }
  end
end
