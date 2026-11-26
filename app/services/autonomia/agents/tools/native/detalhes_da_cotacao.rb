# DETALHES DA COTAÇÃO (#3211): a ferramenta do agente contratado "Seguro Viagem Universal" que lê a ÚLTIMA cotação
# guardada da conversa e devolve os planos pedidos por inteiro (todas as coberturas, com a descrição completa, o preço
# de cada viajante, o preço por dia e por pessoa, as parcelas e a regra de cancelamento). SEM chamada à Universal: o que
# está guardado é o que vale.
#
# Lista branca (R2): só os campos abaixo saem; comissão, markup, ranking e afins nunca chegam aqui (`Planos.de` já os
# deixou de fora). O preço por pessoa usa as idades do pedido guardado e a mesma regra de faixa da cotação (R4, R6).
class Autonomia::Agents::Tools::Native::DetalhesDaCotacao < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem

  class << self
    include SeguroViagem::PortaDoContratado

    # Só lê.
    def escreve? = false

    def slug
      'detalhes_da_cotacao'
    end

    def tool_name
      'Detalhes da cotação do seguro viagem'
    end

    def description
      'Devolve os detalhes da última cotação desta conversa, sem cotar de novo: todas as coberturas com a descrição ' \
        'completa, o preço de cada viajante, o preço por dia e por pessoa, as parcelas e a regra de cancelamento dos ' \
        'planos pedidos. Use quando o cliente perguntar o que um plano cobre ou quanto cada pessoa paga. Lista vazia ' \
        'devolve todos os planos.'
    end

    def args_registraveis
      %w[codigos_dos_planos]
    end

    def params
      [
        { 'name' => 'codigos_dos_planos', 'type' => 'array', 'items' => 'string', 'required' => true,
          'description' => 'Códigos dos planos da última cotação desta conversa. Lista vazia: todos.' }
      ]
    end
  end

  def call
    return error('cotacao_sem_conversa') if conversa.nil?

    cotacao = Autonomia::Agents::CotacaoDeViagem.ultima_da_conversa(conversa.id, agent.id)
    return recusar('sem_cotacao', 'Esta conversa ainda não tem cotação. Cote primeiro.') if cotacao.nil?

    escolhidos, desconhecidos = escolher(cotacao)
    unless desconhecidos.empty?
      return recusar('plano_inexistente', "Planos que não estão na última cotação: #{desconhecidos.join(', ')}. Os " \
                                          "códigos são #{cotacao.planos.pluck('codigo').join(', ')}.",
                     faltando: ['codigos_dos_planos'])
    end

    JSON.generate({ planos: escolhidos.map { |plano| detalhe(plano, cotacao) } })
  end

  private

  # -> [planos escolhidos, códigos que a cotação não tem]. Lista vazia ou ausente: todos os planos.
  def escolher(cotacao)
    codigos = Array(params['codigos_dos_planos']).map { |codigo| codigo.to_s.strip.upcase }.reject(&:empty?)
    return [cotacao.planos.to_a, []] if codigos.empty?

    [cotacao.planos.to_a.select { |plano| codigos.include?(plano['codigo']) },
     codigos.reject { |codigo| cotacao.plano(codigo) }]
  end

  def detalhe(plano, cotacao)
    {
      'codigo' => plano['codigo'], 'nome' => plano['nome'], 'descricao_adicional' => plano['descricao_adicional'],
      'preco_total' => reais(plano['preco_total']),
      'preco_por_pessoa' => SeguroViagem::Faixas.precos_por_pessoa(plano, cotacao.idades).map { |valor| reais(valor) },
      'por_dia_por_pessoa' => SeguroViagem::PorDia.por_pessoa(plano, cotacao.pedido),
      'max_parcelas' => plano['max_parcelas'], 'cambio' => plano['cambio'], 'moeda' => plano['moeda'],
      'idade_minima' => plano['idade_minima'], 'idade_maxima' => plano['idade_maxima'],
      'regra_cancelamento' => plano['regra_cancelamento'].to_a,
      'coberturas' => plano['coberturas'].to_a.map do |cobertura|
        cobertura.slice('id_beneficio', 'nome', 'descricao_completa', 'valor', 'moeda')
      end
    }
  end

  # Valor ausente (idade sem faixa, preço não guardado) fica nil: nunca um preço inventado.
  def reais(valor)
    valor.nil? ? nil : SeguroViagem::Dinheiro.brl(valor)
  end

  def conversa
    delivery.try(:conversation)
  end
end
