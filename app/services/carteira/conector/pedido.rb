# O andamento de uma busca no conector (E7, #2900): o período pedido, o identificador do pedido e o ponto da lista em
# que a busca está, e como cada seguradora respondeu. Mora no item 0 da leitura (estado `pedido`), porque `totais` só
# guarda contagens e a busca não pede coluna nova. O item sai com os outros quando a guarda da leitura vence. Este item não
# é registro do conector: por isso é lido aqui, e não pelo Carteira::ItemLido.
#
# `sync_id` e `cursor` são opacos (só o conector sabe o que têm dentro): são guardados e devolvidos, nunca lidos, e não
# vão para log nem argumento de job. `por_seguradora` só tem o nome da seguradora e a situação dela.
class Carteira::Conector::Pedido
  POSICAO = 0
  ESTADO = 'pedido'.freeze
  SITUACOES = %w[pronta buscando pede_login sem_login falhou].freeze

  def self.criar!(leitura, desde:, ate:)
    leitura.itens.create!(posicao: POSICAO, estado: ESTADO, campos: { 'desde' => desde.iso8601, 'ate' => ate.iso8601 })
  end

  # Depois da guarda, o item sai: a busca trazida fica sem o andamento, e quem lê recebe vazio.
  def initialize(leitura)
    @leitura = leitura
    @item = leitura.itens.find_by(posicao: POSICAO, estado: ESTADO)
  end

  def desde = campos['desde']
  def ate = campos['ate']
  def sync_id = campos['sync_id']
  def cursor = campos['cursor']
  def status = campos['status']
  def pagina = campos['pagina'].to_i
  # A primeira posição dos registros deste pedido: os de antes vieram num pedido anterior da mesma busca (Carteira::Conector::Ler).
  def desde_posicao = campos['desde_posicao'].to_i

  # [{ 'nome' => 'Seguradora X' | nil, 'situacao' => 'pronta' }]
  def por_seguradora
    Array(campos['por_seguradora'])
  end

  def pedido!(sync_id, status)
    desde = (@leitura.itens.maximum(:posicao) || POSICAO) + 1
    mudar!('sync_id' => sync_id, 'status' => status, 'cursor' => nil, 'pagina' => 0, 'desde_posicao' => desde)
  end

  def andamento!(status, seguradoras)
    mudar!('status' => status, 'por_seguradora' => seguradoras_da_tela(seguradoras))
  end

  def proxima_pagina!(cursor)
    mudar!('cursor' => cursor, 'pagina' => pagina + 1)
  end

  # Buscar de novo: o mesmo período, um pedido novo. As seguradoras ficam até o próximo andamento chegar.
  def de_novo!
    mudar!('sync_id' => nil, 'status' => nil, 'cursor' => nil, 'pagina' => 0)
  end

  private

  def campos
    @item ? @item.campos.to_h : {}
  end

  def mudar!(valores)
    raise ActiveRecord::RecordNotFound, 'pedido' unless @item

    @item.update!(campos: campos.merge(valores))
  end

  # Só o nome e a situação, em vocabulário nosso. A situação que não conhecemos vira `falhou`: a tela diz "não deu para
  # buscar agora" e oferece buscar de novo, em vez de calar.
  def seguradoras_da_tela(seguradoras)
    Array(seguradoras).select { |seguradora| seguradora.is_a?(Hash) }.map do |seguradora|
      situacao = seguradora['situacao'].to_s
      { 'nome' => seguradora['nome'].presence&.to_s&.truncate(120), 'situacao' => SITUACOES.include?(situacao) ? situacao : 'falhou' }
    end
  end
end
