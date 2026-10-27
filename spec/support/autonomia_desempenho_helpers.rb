# Painel de desempenho (#2251): uma ficha e procuras INVENTADAS (uma loja genérica), nunca dado de cliente.
module AutonomiaDesempenhoHelpers
  CATALOGO_DA_LOJA = {
    'temas' => { 'entrega' => 'Prazo de entrega', 'troca' => 'Troca de produto' },
    'marcos' => { 'orcamento_enviado' => 'Orçamento enviado', 'pagou' => 'Pagou' },
    'motivos' => { 'sem_estoque' => 'Sem estoque' },
    'regras' => { 'R-PRAZO' => { 'nome' => 'Dizer o prazo', 'descricao' => 'Sempre dizer o prazo.' } },
    'resultados' => {
      'comprou' => { 'nome' => 'Comprou', 'grupo' => 'fechou' },
      'vai_pensar' => { 'nome' => 'Vai pensar', 'grupo' => 'parou' },
      'duvida_resolvida' => { 'nome' => 'Dúvida resolvida', 'grupo' => 'resolveu' }
    },
    'origens' => { 'desconhecida' => { 'nome' => 'Não sabemos', 'tipo' => 'sem_anuncio' } },
    'quem' => { 'cliente' => 'Cliente final' },
    'cortes' => { 'pedido' => { 'comprar' => 'Comprar', 'duvida' => 'Dúvida' } }
  }.freeze

  CONFIGURACAO_DA_LOJA = {
    'meta' => { 'agente' => { 'id' => nil, 'nome' => 'Atendente', 'origem' => 'webhook', 'foto_url' => nil },
                'conta' => { 'nome' => 'Loja' }, 'fuso' => 'America/Sao_Paulo',
                'horario_comercial' => { 'dias_semana' => [1, 2, 3, 4, 5], 'inicio_hora' => 9, 'fim_hora' => 18 },
                'nomes' => { 'compra' => 'Pedidos de compra' }, 'definicoes' => [] },
    'compra_pedidos' => ['comprar'], 'duvida_pedidos' => ['duvida'], 'duvida_resolvida' => ['duvida_resolvida'],
    'funil' => [{ 'id' => 'pedido', 'nome' => 'Pediu', 'marcos' => [] },
                # Etapa cujo id difere dos marcos (vale a lista) e etapa sem lista (vale o id): a regra dos três lados.
                { 'id' => 'recebeu_orcamento', 'nome' => 'Recebeu o orçamento', 'marcos' => ['orcamento_enviado'] },
                { 'id' => 'pagou', 'nome' => 'Pagou', 'marcos' => [] }],
    'funil_nota' => nil, 'comparacoes' => [], 'cortes' => [{ 'id' => 'pedido', 'nome' => 'Pedido', 'base' => 'todas', 'campo' => 'pedido' }],
    'regras_sistemicas' => [], 'nomes_horario' => { 'fora' => 'Fora do horário', 'dentro' => 'No horário' },
    'marcos_da_passagem' => nil, 'anuncios_ligados' => false, 'anuncios' => [], 'origem_nota' => nil,
    'remetentes_do_agente' => [%w[AgentBot 0]]
  }.freeze

  def ficha_da_loja!(account, sujeito_id:, versao: 1, remetentes: nil)
    configuracao = CONFIGURACAO_DA_LOJA.deep_dup
    configuracao['remetentes_do_agente'] = remetentes || [['AgentBot', sujeito_id]]
    Autonomia::Desempenho::Ficha.create!(account: account, sujeito_type: 'robo', sujeito_id: sujeito_id, versao: versao, lote: 'spec',
                                         catalogo: CATALOGO_DA_LOJA.deep_dup, configuracao: configuracao,
                                         referencias: { 'ticket' => nil, 'confianca' => nil, 'exemplos' => {} })
  end

  # Uma procura lida; `inicio` é a hora local (America/Sao_Paulo) em texto 'AAAA-MM-DD HH:MM'.
  def procura_da_loja!(conversa, sujeito_id:, inicio:, ordem: 1, **campos)
    em = ActiveSupport::TimeZone['America/Sao_Paulo'].parse(inicio)
    Autonomia::Desempenho::Procura.create!({
      account: conversa.account, sujeito_type: 'robo', sujeito_id: sujeito_id, conversation: conversa, ordem: ordem,
      inicio_em: em, fim_em: em + 10.minutes, versao_ficha: 1, lote: 'spec', pedido_id: 'comprar', tema_id: 'entrega',
      resultado_id: 'vai_pensar', qualidade_id: 'acertou', origem_id: 'desconhecida', quem_id: 'cliente',
      dados: { 'cortes' => { 'pedido' => 'comprar' }, 'resumo' => 'Quer saber o prazo.', 'por_que' => nil }
    }.merge(campos))
  end

  def leitura_da_loja!(conversa, sujeito_id:, ate:)
    Autonomia::Desempenho::Leitura.create!(account: conversa.account, sujeito_type: 'robo', sujeito_id: sujeito_id, conversation: conversa,
                                           lida_ate_em: ActiveSupport::TimeZone['America/Sao_Paulo'].parse(ate), versao_ficha: 1,
                                           status: 'lida', lote: 'spec')
  end
end

RSpec.configure { |config| config.include AutonomiaDesempenhoHelpers }
