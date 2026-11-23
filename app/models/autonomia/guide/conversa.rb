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
  #
  # A mensagem que a pessoa mandou enquanto o Guia trabalhava (`Turno::JUNTO`) entra no lugar do turno que a
  # respondeu, na ordem em que ela escreveu e antes da resposta: é assim que o modelo entende que a resposta já
  # cuidou dela. Junta cujo turno ficou fora da janela entra sozinha, como fala da pessoa.
  #
  # `exceto`: o pedido que vai ser respondido agora fica fora, com as mensagens juntas a ele — elas são a pergunta.
  def historico(limite: ::Autonomia::Guide::Chat::MAX_HISTORY, exceto: nil)
    recentes = turnos.reorder(created_at: :desc, id: :desc).limit(limite)
                     .select(:id, :pedido_id, :pergunta, :resposta, :diagnostico, :status, :created_at).reverse
    pais = recentes.reject(&:junto_de).map(&:pedido_id)
    juntas = recentes.select(&:junto_de).group_by(&:junto_de)
    recentes.flat_map { |turno| mensagens_no_historico(turno, pais, juntas, exceto) }.last(limite)
  end

  def resumo
    { 'id' => id, 'titulo' => titulo, 'atualizada_em' => updated_at.iso8601 }
  end

  def para_tela
    { 'id' => id, 'titulo' => titulo, 'atualizada_em' => updated_at.iso8601,
      'turnos' => turnos.includes(:execucao).map(&:para_tela) }
  end

  private

  def mensagens_no_historico(turno, pais, juntas, exceto)
    pai = turno.junto_de
    return [] if exceto.present? && [turno.pedido_id, pai].include?(exceto)
    return [] if pai && pais.include?(pai)
    return [{ role: 'user', content: turno.pergunta }] if pai

    com_juntas(turno, juntas[turno.pedido_id])
  end

  def com_juntas(turno, juntas)
    return turno.mensagens if juntas.blank? || turno.aviso_id

    falas = (juntas + [turno]).sort_by { |t| [t.created_at, t.id] }.map { |t| { role: 'user', content: t.pergunta } }
    falas + turno.mensagens.drop(1)
  end
end
