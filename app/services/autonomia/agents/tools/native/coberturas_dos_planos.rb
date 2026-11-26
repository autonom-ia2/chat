# COBERTURAS DOS PLANOS (#3249): a ferramenta do agente contratado "Seguro Viagem Universal" que responde o valor das
# coberturas de um plano ANTES da cotação ("quanto o Master cobre de despesa médica?"), pelo catálogo da Universal
# (`Universal::Cliente#beneficios`, guardado por um dia). Depois da cotação, a fonte continua `detalhes_da_cotacao`.
#
# SEM PREÇO: o catálogo não tem, e o preço só sai da cotação. Devolve, por plano encontrado, o nome do plano no catálogo
# e as coberturas `{ nome, valor }`, com o valor como veio (no internacional, em dólar). O casamento do nome e o fato
# medido sobre os planos "USA +" estão em `SeguroViagem::CatalogoDeCoberturas`. Nome que não casa: recusa com os nomes
# que existem.
#
# Só lê, e não precisa de conversa (o catálogo é o mesmo para todas). NUNCA LEVANTA com a seguradora fora: o erro do
# cliente HTTP passa por `SeguroViagem::Falhas`, como nas outras ferramentas; não há dado do cliente a corrigir, então o
# pedido inválido vira indisponível.
class Autonomia::Agents::Tools::Native::CoberturasDosPlanos < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Catalogo = SeguroViagem::CatalogoDeCoberturas

  AVISO = 'Sem preço: o preço só sai na cotação.'.freeze
  AVISO_INTERNACIONAL = 'Valores com "$" são em dólar. Cada plano "USA +" tem as mesmas coberturas do plano de mesmo ' \
                        'nome sem "USA" (Master +, Value +, Exclusive +), que vale para os outros destinos.'.freeze

  class << self
    include SeguroViagem::PortaDoContratado

    # Só lê.
    def escreve? = false

    def slug
      'coberturas_dos_planos'
    end

    def tool_name
      'Coberturas dos planos do seguro viagem'
    end

    def description
      'Devolve as coberturas e o valor de cada uma dos planos pedidos, pelo catálogo da seguradora, sem cotar. Use ' \
        'quando o cliente perguntar quanto um plano cobre antes de ter cotação. Não traz preço. Lista vazia devolve ' \
        'todos os planos.'
    end

    def args_registraveis
      %w[planos nacional]
    end

    def params
      [
        { 'name' => 'planos', 'type' => 'array', 'items' => 'string', 'required' => true,
          'description' => 'Nomes dos planos como o cliente ou a base escrevem, por exemplo "Master", "Value +" ou ' \
                           '"Exclusive USA +". Lista vazia: todos.' },
        { 'name' => 'nacional', 'type' => 'boolean', 'required' => true,
          'description' => 'true quando a viagem é só dentro do Brasil; false para viagem ao exterior.' }
      ]
    end
  end

  def call
    planos = Catalogo.planos(cliente.beneficios(nacional: nacional?))
    escolhidos, desconhecidos = Catalogo.escolher(planos, params['planos'])
    return fora_do_catalogo(desconhecidos, planos) unless desconhecidos.empty?

    JSON.generate({ catalogo: nacional? ? 'nacional' : 'internacional', aviso: aviso,
                    planos: escolhidos.map { |plano| plano.slice('plano', 'coberturas') } })
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
    SeguroViagem::Falhas.tratar_sem_dado_do_cliente(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  private

  def fora_do_catalogo(desconhecidos, planos)
    recusar('plano_fora_do_catalogo', "Planos que não estão no catálogo: #{desconhecidos.join(', ')}. Os planos do " \
                                      "catálogo são: #{planos.pluck('plano').join(', ')}.", faltando: ['planos'])
  end

  def aviso
    nacional? ? AVISO : "#{AVISO} #{AVISO_INTERNACIONAL}"
  end

  # A ferramenta nativa recebe os argumentos como o modelo mandou (`Bound#run_native`, sem `ParamsTipados`): vale `true`
  # e o texto "true"; qualquer outra coisa é viagem ao exterior.
  def nacional?
    [true, 'true'].include?(params['nacional'])
  end

  def cliente
    acesso = agent.acesso_da_seguradora
    Autonomia::Seguradoras::Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end

  def conversa
    delivery.try(:conversation)
  end
end
