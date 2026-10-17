# O que a avaliação de card recebe da memória (#1601, W4), montado para o ContextBuilder:
#   memoria_refs    { "m1" => message_id } dos ids LOCAIS que o modelo vê (A10); nunca vai ao modelo
#   memoria_token   o agendamento que esta avaliação atende, lido antes da chamada (a superada não grava)
#   memoria_fatos   os fatos vivos deste card, do contato e das conversas do card, com id e versão (até 40)
#   memoria_chaves  as chaves com vários itens e as que identificam o item (a placa)
module Crm::Memoria::ParaAvaliacao
  MAX_FATOS = 40
  GRUPO_DO_ESCOPO = { 'card' => 'pedido', 'contato' => 'contato', 'conversa' => 'conversa' }.freeze

  # Numera as mensagens na ordem em que vão ao modelo.
  class Numeracao
    attr_reader :mapa

    def initialize
      @mapa = {}
    end

    def ref_de(message)
      ref = "m#{@mapa.size + 1}"
      @mapa[ref] = message.id
      { ref: ref }
    end
  end

  module_function

  def contexto(card, conversation_ids, numeracao)
    { memoria_refs: numeracao.mapa.dup, memoria_token: card.metadata.to_h.dig('ai', 'evaluate_token'),
      memoria_fatos: fatos(card, conversation_ids), memoria_chaves: chaves(card.account) }
  end

  def fatos(card, conversation_ids)
    vivos = Crm::MemoriaFato.vivos.where(account_id: card.account_id, contact_id: card.contact_id)
    vivos = vivos.where(escopo: 'card', card_id: card.id).or(vivos.where(escopo: 'contato'))
                 .or(vivos.where(escopo: 'conversa', conversation_id: conversation_ids))
    vivos.order(registrado_em: :desc).limit(MAX_FATOS).map { |fato| linha(fato) }
  end

  def linha(fato)
    { id: fato.id, grupo: fato.tipo == 'decisao' ? 'decisao' : GRUPO_DO_ESCOPO.fetch(fato.escopo), chave: fato.chave,
      item_ref: fato.item_ref.presence, valor: fato.valor, versao: fato.versao, fonte: fato.fonte, status: fato.status,
      situacao: fato.situacao, desde: fato.valido_desde.iso8601 }
  end

  def chaves(account)
    Crm::Memoria::Catalogo.da_conta(account).values
                          .select { |chave| chave.attribute_model != Crm::Memoria::Catalogo::SISTEMA && (chave.varios? || chave.item_natural?) }
                          .map { |chave| { chave: chave.chave, cardinalidade: chave.varios? ? 'N' : '1', item_natural: chave.item_natural? } }
  end
end
