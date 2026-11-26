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
        'quando o cliente perguntar quanto um plano cobre antes de ter cotação. Com o nome do plano, não pergunte se a ' \
        'viagem é no Brasil ou no exterior: ela acha o plano nos catálogos nacional e internacional. Não traz preço. ' \
        'Lista vazia devolve todos os planos.'
    end

    def args_registraveis
      %w[planos nacional]
    end

    def params
      [
        { 'name' => 'planos', 'type' => 'array', 'items' => 'string', 'required' => true,
          'description' => 'Nomes dos planos como o cliente ou a base escrevem, por exemplo "Master", "Value +" ou ' \
                           '"Exclusive USA +". Lista vazia: todos.' },
        { 'name' => 'nacional', 'type' => 'boolean', 'required' => false,
          'description' => 'Só quando o cliente já disse que a viagem é toda dentro do Brasil (true) ou ao exterior ' \
                           '(false). Com o nome do plano, deixe null: a ferramenta procura nos dois catálogos.' }
      ]
    end
  end

  # Com `nacional` explícito lê só aquele catálogo. Sem ele (nil), procura cada nome nos DOIS catálogos (cada um com o
  # seu cache de 24 h): o nome do plano já diz o catálogo, e o cliente que pergunta "quanto cobre o Master?" não sabe
  # (nem precisa saber) se a viagem é nacional. Nome achado nos dois (não deve acontecer): vale o internacional.
  def call
    catalogos = ler_catalogos
    escolhidos, desconhecidos = escolher(catalogos)
    fora_do_ar = catalogos.any? { |catalogo| catalogo[:erro] }
    return tratar_falha(catalogos) if escolhidos.empty? && fora_do_ar
    # Com um catálogo fora, o nome que não apareceu pode estar nele: não é "fora do catálogo" (o aviso diz isso).
    return fora_do_catalogo(desconhecidos, catalogos) if desconhecidos.any? && !fora_do_ar

    responder(escolhidos, catalogos)
  end

  private

  # -> [{ nome: 'internacional' | 'nacional', planos: [...] }] ou, com a Universal fora, `{ nome:, erro: }`. Só o erro do
  # cliente HTTP é guardado; qualquer outro levanta.
  def ler_catalogos
    consultados.map do |nacional|
      nome = nacional ? 'nacional' : 'internacional'
      { nome: nome, planos: Catalogo.planos(cliente.beneficios(nacional: nacional)) }
    rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
      { nome: nome, erro: e }
    end
  end

  # Internacional primeiro: é ele que vence quando o mesmo nome existe nos dois.
  def consultados
    return [false, true] if params['nacional'].nil?

    [nacional?]
  end

  # -> [[{ 'plano', 'coberturas', 'catalogo' }], nomes que nenhum catálogo consultado tem]
  def escolher(catalogos)
    consultaveis = catalogos.reject { |catalogo| catalogo[:erro] }
    pedidos = Array(params['planos']).map { |pedido| pedido.to_s.strip }.reject(&:empty?)
    return [consultaveis.flat_map { |catalogo| marcar(catalogo, catalogo[:planos]) }, []] if pedidos.empty?

    achados = pedidos.index_with { |pedido| achar_em_ordem(consultaveis, pedido) }
    [achados.values.flatten(1).uniq { |plano| [plano['catalogo'], plano['plano']] }, sem_achado(achados)]
  end

  def sem_achado(achados)
    achados.select { |_pedido, planos| planos.empty? }.keys
  end

  # O primeiro catálogo que tem o nome responde; o seguinte só é lido quando o anterior não tem.
  def achar_em_ordem(catalogos, pedido)
    catalogos.each do |catalogo|
      achados, = Catalogo.escolher(catalogo[:planos], [pedido])
      return marcar(catalogo, achados) if achados.any?
    end
    []
  end

  def marcar(catalogo, planos)
    planos.map { |plano| plano.slice('plano', 'coberturas').merge('catalogo' => catalogo[:nome]) }
  end

  def responder(escolhidos, catalogos)
    nomes = escolhidos.pluck('catalogo').uniq
    JSON.generate({ catalogo: nomes.join(' e '), aviso: aviso(nomes, catalogos),
                    planos: nomes.size > 1 ? escolhidos : escolhidos.map { |plano| plano.except('catalogo') } })
  end

  def fora_do_catalogo(desconhecidos, catalogos)
    planos = catalogos.flat_map { |catalogo| catalogo[:planos] }
    recusar('plano_fora_do_catalogo', "Planos que não estão no catálogo: #{desconhecidos.join(', ')}. Os planos do " \
                                      "catálogo são: #{planos.pluck('plano').join(', ')}.", faltando: ['planos'])
  end

  # Nada foi achado e há catálogo que não respondeu: a falha da seguradora, como nas outras ferramentas.
  def tratar_falha(catalogos)
    erro = catalogos.filter_map { |catalogo| catalogo[:erro] }.first
    SeguroViagem::Falhas.tratar_sem_dado_do_cliente(erro, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  def aviso(nomes, catalogos)
    texto = nomes.include?('internacional') ? "#{AVISO} #{AVISO_INTERNACIONAL}" : AVISO
    fora = catalogos.select { |catalogo| catalogo[:erro] }.pluck(:nome)
    fora.empty? ? texto : "#{texto} Catálogo #{fora.join(' e ')} fora do ar agora: o que não foi achado pode estar nele."
  end

  # A ferramenta nativa recebe os argumentos como o modelo mandou (`Bound#run_native`, sem `ParamsTipados`): vale `true`
  # e o texto "true"; qualquer outra coisa informada é viagem ao exterior. Ausente (nil) é tratado em `consultados`.
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
