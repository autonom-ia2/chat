# "Trazer minha lista" com seguros (E4, #2897): os seguros que uma lista trazida pôs na carteira, diante de como estão
# hoje. É por aqui que o "Desfazer" da lista (Relacionamentos::Trazer::Desfazer) e a prévia dele sabem o que sai, o que
# volta e o que fica: o que a prévia promete é o que o Desfazer faz.
#
# Nada novo é anotado para isso. Vale o que o gravador único já deixa (Carteira::Guardar):
# - a apólice que a lista CRIOU aponta para a importação (`campaign_import_id`) e tem o passo `chegou_planilha` dela;
# - a apólice que a lista só COMPLETOU (já existia) ganhou o passo `chegou_de_novo` da importação, com o antes e o
#   depois de cada campo (`mudancas`, na forma do banco).
#
# SAI só o seguro que a lista criou e em que ninguém mexeu depois. "Ninguém mexeu" é: a história dele só tem passos
# desta lista (nada de correção, cancelamento, PDF, renovação, outra lista ou outra fonte); não tem PDF guardado nem
# leitura de PDF apontando para ele; não tem card de renovação, desfecho (renovou, não renovou), apólice anterior nem
# apólice nova; não foi cancelado nem corrigido à mão; e a origem continua sendo a planilha. Na dúvida, fica.
#
# VOLTA ao que era o seguro que já existia e que a lista só completou, se ninguém mudou depois: nenhum passo de outra
# origem veio depois do passo desta lista, o seguro não está cancelado e cada campo que a lista mudou ainda tem o valor
# que ela pôs. Voltam todos os campos que a lista mudou nele, ou nenhum. O ramo como estava escrito antes não é
# guardado pelo gravador: quando o tipo volta, o ramo escrito fica o da planilha (limite conhecido).
#
# FICA todo o resto: o que a lista criou e alguém já cuidou, e o que ela completou e alguém mudou depois.
#
# Tudo é lido só dentro da conta da importação. Nada daqui vai para o log.
class Carteira::Trazer::SegurosDaLista
  DE_NOVO = Carteira::Guardar::DE_NOVO
  PLANILHA = Carteira::Trazer::SeguroDaLinha::ORIGEM
  BLOCO = 500
  # O que só é preenchido depois de o seguro chegar, por alguém ou por outra parte do sistema: o cancelamento, a
  # renovação (card, card apagado, desfecho, apólice anterior), a leitura de PDF e o que saiu dela para o cliente.
  DEPOIS_DA_LISTA = %i[
    cancelado_em crm_card_id renovacao_card_removido_em apolice_anterior_id renovado_em nao_renovou_em leitura_id
    lembrete_aceito_em palavras_texto palavras_enviadas_em
  ].freeze
  COMO_CHEGOU = "carteira_apolices.corrigido_a_mao = '[]'::jsonb AND carteira_apolices.duvidas = '[]'::jsonb".freeze
  SO_PASSOS_DA_LISTA = 'NOT EXISTS (SELECT 1 FROM carteira_apolice_eventos passo WHERE passo.apolice_id = carteira_apolices.id ' \
                       'AND passo.campaign_import_id IS DISTINCT FROM ?)'.freeze
  SEM_PDF = "NOT EXISTS (SELECT 1 FROM active_storage_attachments anexo WHERE anexo.record_type = 'Carteira::Apolice' " \
            'AND anexo.record_id = carteira_apolices.id)'.freeze
  SEM_APOLICE_NOVA = 'NOT EXISTS (SELECT 1 FROM carteira_apolices nova WHERE nova.apolice_anterior_id = carteira_apolices.id)'.freeze
  SEM_LEITURA_DE_PDF = 'NOT EXISTS (SELECT 1 FROM carteira_leitura_itens item WHERE item.apolice_id = carteira_apolices.id)'.freeze

  def initialize(importacao)
    @importacao = importacao
    @conta_id = importacao.account_id
  end

  # A lista pôs alguma coisa na carteira (criou seguro ou completou algum).
  def tem?
    return @tem if defined?(@tem)

    @tem = criados.exists? || passos_da_lista.exists?
  end

  # A pessoa disse, na conferência, que esta planilha tinha seguros. Ao contrário de `tem?`, não muda quando o Desfazer
  # tira os seguros: a prévia e o Desfazer perguntam a mesma coisa, e a lista sem seguros não custa consulta nenhuma.
  def trouxe_seguros?
    colunas = Carteira::Trazer::ColunasDeSeguro
    ContactImports::Trazer::Conferencia.new(@importacao).respostas[colunas::RESPOSTA] == colunas::SIM
  end

  # Os seguros que a lista criou e em que ninguém mexeu depois.
  def saem
    criados.where(origem: PLANILHA, de_fora: false, **DEPOIS_DA_LISTA.index_with { nil })
           .where(COMO_CHEGOU).where(SO_PASSOS_DA_LISTA, @importacao.id)
           .where(SEM_PDF).where(SEM_APOLICE_NOVA).where(SEM_LEITURA_DE_PDF)
  end

  def sai?(apolice)
    saem.exists?(id: apolice.id)
  end

  # Os seguros da conta que continuam na carteira depois deste Desfazer: seguram a pessoa (ela não sai da base) e a
  # marca de cliente dela (Relacionamentos::Trazer::QuemFica, Relacionamentos::Trazer::CamposDaLista).
  def que_ficam
    todos = Carteira::Apolice.where(account_id: @conta_id)
    tem? ? todos.where.not(id: saem.select(:id)) : todos
  end

  # Bloco a bloco, os seguros que a lista só completou e que voltam ao que eram: [apólice, { coluna => valor de antes }].
  def que_voltam
    completados.in_batches(of: BLOCO) do |apolices|
      passos = Carteira::ApoliceEvento.where(apolice_id: apolices.select(:id)).order(:id).group_by(&:apolice_id)
      voltam = apolices.filter_map do |apolice|
        colunas = colunas_de_antes(apolice, passos.fetch(apolice.id, []))
        [apolice, colunas] if colunas
      end
      yield voltam
    end
  end

  # O que a apólice volta a ter, lido de novo (o Desfazer chama com a apólice travada). nil: ela fica como está.
  def volta(apolice)
    colunas_de_antes(apolice, apolice.eventos.order(:id).to_a)
  end

  # Os passos que esta lista deixou na história de uma apólice.
  def passos_da_lista_em(apolice)
    passos_da_lista.where(apolice_id: apolice.id)
  end

  # Para a tela: quantos seguros saem, quantos voltam ao que eram e quantos ficam como estão.
  def previa
    saem = self.saem.count
    voltam = 0
    que_voltam { |bloco| voltam += bloco.size }
    { saem: saem, ficam: (criados.count - saem) + (completados.count - voltam), voltam: voltam }
  end

  private

  def criados
    Carteira::Apolice.where(account_id: @conta_id, campaign_import_id: @importacao.id)
  end

  def passos_da_lista
    Carteira::ApoliceEvento.where(campaign_import_id: @importacao.id)
  end

  # Os que já existiam e em que a lista mudou algum campo.
  def completados
    mudados = passos_da_lista.where(tipo: DE_NOVO).where.not(mudancas: nil).select(:apolice_id)
    Carteira::Apolice.where(account_id: @conta_id, id: mudados).where('carteira_apolices.campaign_import_id IS DISTINCT FROM ?', @importacao.id)
  end

  # passos: a história inteira da apólice, do mais antigo para o mais novo.
  def colunas_de_antes(apolice, passos)
    da_lista, de_fora = passos.partition { |passo| passo.campaign_import_id == @importacao.id }
    return unless ninguem_mexeu_depois?(apolice, da_lista, de_fora)

    desfazer_mudancas(apolice, da_lista.reverse.flat_map { |passo| Array(passo.mudancas).reverse })
  end

  # A lista deixou passo na história dele, ele não está cancelado e nenhum passo de outra origem veio depois do dela.
  def ninguem_mexeu_depois?(apolice, da_lista, de_fora)
    ultimo = da_lista.map(&:id).max
    return false if ultimo.nil? || apolice.cancelado_em

    de_fora.none? { |passo| passo.id > ultimo }
  end

  # mudancas: da mais nova para a mais velha. Cada campo tem de estar com o valor que a lista pôs; aí volta ao de antes.
  def desfazer_mudancas(apolice, mudancas)
    de_antes = {}
    mudancas.each do |mudanca|
      coluna = Carteira::Campos::COLUNAS[mudanca['campo']]
      return nil if coluna.nil?

      agora = de_antes.fetch(coluna) { Carteira::Campos.guardado(apolice[coluna]) }
      return nil unless agora == mudanca['depois']

      de_antes[coluna] = mudanca['antes']
    end
    de_antes.presence
  end
end
