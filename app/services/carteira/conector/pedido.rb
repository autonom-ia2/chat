# O andamento de uma busca no conector (E7, #2900): o período pedido, o identificador do pedido, o ponto da lista em
# que a busca está e os avisos das seguradoras. Mora no item 0 da leitura (estado `pedido`), porque `totais` só
# guarda contagens e a busca não pede coluna nova. O item sai com os outros quando a guarda da leitura vence. Este item não
# é registro do conector: por isso é lido aqui, e não pelo Carteira::ItemLido.
#
# `sync_id` e `cursor` são opacos (só o conector sabe o que têm dentro): são guardados e devolvidos, nunca lidos, e não
# vão para log nem argumento de job.
#
# Os avisos (`avisos`) vêm do pedido (`portfolio_sync_start`, campo `por_seguradora`), e só com EVIDÊNCIA do cadastro de
# logins da corretora no Agger (#2900, E7.5): `sem_login` (a corretora não guardou o login da seguradora) ou
# `pede_login` (o login guardado não vale mais). Só o nome da seguradora e a situação. Sem o campo (o adapter de antes, ou
# o cadastro que não deu para ler), nenhum aviso: nada é deduzido. O `status` só existe na busca pedida antes desta
# regra, que ainda espera o robô (Carteira::Conector::Sincronizar::PRAZO_DO_ROBO).
class Carteira::Conector::Pedido
  POSICAO = 0
  ESTADO = 'pedido'.freeze
  SITUACOES_COM_AVISO = %w[pede_login sem_login].freeze

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
  # Quando a busca começou (o item nasce com ela): o prazo da busca de antes que ainda espera o robô.
  def comecou_em = @item&.created_at || Time.current

  # [{ 'nome' => 'Seguradora X' | nil, 'situacao' => 'sem_login' | 'pede_login' }]
  def por_seguradora
    Array(campos['avisos'])
  end

  def pedido!(sync_id, avisos:)
    desde = (@leitura.itens.maximum(:posicao) || POSICAO) + 1
    mudar!('sync_id' => sync_id, 'status' => nil, 'cursor' => nil, 'pagina' => 0, 'desde_posicao' => desde, 'avisos' => avisos_da_tela(avisos))
  end

  # Só a busca de antes, que ainda pergunta pelo robô.
  def andamento!(status)
    mudar!('status' => status)
  end

  def proxima_pagina!(cursor)
    mudar!('cursor' => cursor, 'pagina' => pagina + 1)
  end

  # Buscar de novo: o mesmo período, um pedido novo. Os avisos do pedido anterior saem junto: enquanto a busca nova
  # anda, a tela não mostra aviso da busca velha (#2900, E7.5).
  def de_novo!
    mudar!('sync_id' => nil, 'status' => nil, 'cursor' => nil, 'pagina' => 0, 'avisos' => [])
  end

  private

  def campos
    @item ? @item.campos.to_h : {}
  end

  def mudar!(valores)
    raise ActiveRecord::RecordNotFound, 'pedido' unless @item

    @item.update!(campos: campos.merge(valores))
  end

  # Só o nome e a situação, e só as situações com evidência. A situação que não conhecemos (ou sem problema) não vira
  # aviso: sem evidência, a tela não diz nada.
  def avisos_da_tela(seguradoras)
    Array(seguradoras).select { |seguradora| seguradora.is_a?(Hash) && SITUACOES_COM_AVISO.include?(seguradora['situacao'].to_s) }
                      .map { |seguradora| { 'nome' => seguradora['nome'].presence&.to_s&.truncate(120), 'situacao' => seguradora['situacao'].to_s } }
  end
end
