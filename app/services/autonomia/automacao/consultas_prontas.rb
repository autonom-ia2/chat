# As consultas prontas do passo "buscar informação em outro sistema" (#2934, decisão do Rodrigo em 12/11: "foco na jornada").
# A pessoa escolhe uma consulta do dia a dia ("Busca de CEP"), diz de onde vem o que ela precisa informar ("o CEP", com
# "Pôr um dado") e recebe os dados com rótulo pronto (Rua, Bairro, Cidade...). Sem IA e sem chave crua de JSON.
#
# Não é uma fonte nova: cada consulta pronta é uma consulta das Ferramentas prontas dos agentes (#2858,
# FerramentasProntas::Catalogo), e a busca roda pela mesma Execucao delas (ConsultaPronta): os mesmos provedores, a
# reserva, o cache, o limite do dia da conta naquela fonte (o mesmo que os agentes gastam) e o corte individual.
#
# Entram só as grátis que servem a um passo de automação com dados que a conta já tem no contato ou no card. As
# Premium (pagas por consulta) ficam de fora até o Rodrigo decidir a cobrança de uma busca que roda em lote (o "para
# cada" pode rodar 200 de uma vez). Loja virtual e Boletos não existem como fonte na plataforma: não entram.
#
# A regra de cada ferramenta vale aqui: a flag das prontas (e a da fase da fonte) e o corte da conta. A consulta que a
# conta não tem aparece na tela com o que falta (`falta`), nunca some.
module Autonomia::Automacao::ConsultasProntas
  # `formato`: como o valor vira texto para a pessoa (e para os passos seguintes).
  Dado = Data.define(:caminho, :formato) do
    def initialize(caminho:, formato: :texto) = super
  end
  # `fonte` e `consulta`: a fonte e a consulta das Ferramentas prontas. `entradas`: os parâmetros que a pessoa informa,
  # na ordem da tela. `fixos`: os que a plataforma deduz (o tipo de veículo da FIPE é carro).
  Pronta = Data.define(:id, :fonte, :consulta, :entradas, :dados, :fixos) do
    def caminhos = dados.map(&:caminho)
  end

  T = 'autonomia.automacao.consultas_prontas'.freeze

  TODAS = [
    Pronta.new(id: 'cep', fonte: 'cep', consulta: 'endereco', entradas: %w[cep], fixos: {},
               dados: %w[logradouro bairro cidade uf cep].map { |caminho| Dado.new(caminho: caminho) }),
    Pronta.new(id: 'cnpj', fonte: 'cnpj', consulta: 'empresa', entradas: %w[cnpj], fixos: {},
               dados: [Dado.new(caminho: 'razao_social'), Dado.new(caminho: 'nome_fantasia'), Dado.new(caminho: 'situacao'),
                       Dado.new(caminho: 'abertura', formato: :data), Dado.new(caminho: 'atividade_principal.descricao'),
                       Dado.new(caminho: 'porte'), Dado.new(caminho: 'cidade'), Dado.new(caminho: 'uf')]),
    Pronta.new(id: 'fipe', fonte: 'fipe', consulta: 'preco', entradas: %w[marca modelo ano], fixos: { 'tipo' => 'carros' },
               dados: [Dado.new(caminho: 'precos.0.valor', formato: :dinheiro), Dado.new(caminho: 'precos.0.modelo'),
                       Dado.new(caminho: 'precos.0.ano_modelo'), Dado.new(caminho: 'precos.0.combustivel'),
                       Dado.new(caminho: 'precos.0.mes_de_referencia', formato: :mes)]),
    Pronta.new(id: 'cpf', fonte: 'cpf', consulta: 'conferir', entradas: %w[cpf], fixos: {},
               dados: [Dado.new(caminho: 'valido', formato: :sim_ou_nao), Dado.new(caminho: 'estados', formato: :lista)])
  ].freeze

  module_function

  def buscar(id) = TODAS.find { |pronta| pronta.id == id.to_s }

  def fonte(pronta) = ::Autonomia::FerramentasProntas::Catalogo.buscar(pronta.fonte)

  # O que falta para a conta usar a consulta, ou nil: 'desligada' (a flag das prontas ou a da fase da fonte) ou 'pausada'
  # (o corte individual da conta naquela fonte).
  def falta(conta, pronta)
    return 'desligada' unless ::Autonomia::FerramentasProntas.disponivel?(conta, fonte(pronta))

    'pausada' if ::Autonomia::FerramentasProntas::Acesso.find_by(account_id: conta.id, fonte: pronta.fonte)&.cortada?
  end

  def nome(pronta) = I18n.t("#{T}.#{pronta.id}.nome")
  def rotulo_da_entrada(pronta, entrada) = I18n.t("#{T}.#{pronta.id}.entradas.#{entrada}")
  def rotulo_do_dado(pronta, caminho) = I18n.t("#{T}.#{pronta.id}.dados.#{caminho.tr('.', '_')}")

  # A lista da tela, com a explicação do que falta para cada uma (a consulta indisponível aparece, nunca some).
  def para_tela(conta)
    TODAS.map do |pronta|
      falta = falta(conta, pronta)
      { id: pronta.id, nome: nome(pronta), faz: I18n.t("#{T}.#{pronta.id}.faz"), limite_do_dia: limite_do_dia(conta, pronta),
        entradas: pronta.entradas.map { |entrada| entrada_para_tela(pronta, entrada) },
        dados: pronta.caminhos.map { |caminho| { caminho: caminho, rotulo: rotulo_do_dado(pronta, caminho) } },
        disponivel: falta.nil?, falta: falta && I18n.t("#{T}.falta.#{falta}") }
    end
  end

  def entrada_para_tela(pronta, entrada)
    { nome: entrada, rotulo: rotulo_da_entrada(pronta, entrada), exemplo: I18n.t("#{T}.#{pronta.id}.exemplos.#{entrada}", default: '') }
  end

  # O limite do dia que a conta gasta nesta fonte (o mesmo dos agentes): o da conta, se a plataforma deu um, ou o do
  # catálogo.
  def limite_do_dia(conta, pronta)
    acesso = ::Autonomia::FerramentasProntas::Acesso.find_by(account_id: conta.id, fonte: pronta.fonte)
    acesso ? acesso.limite_do_dia : fonte(pronta)&.limite_diario
  end

  # A conferência do salvar: a consulta existe e a conta pode usá-la, cada entrada foi dita e cada dado guardado é um
  # dos que ela devolve. Os valores das entradas (`$valor`) a Receita confere com a régua de sempre (Leitura).
  def problemas(id, passo, conta)
    pronta = buscar(passo.dig('fonte', 'consulta'))
    return [texto(:pronta_desconhecida, passo: id)] unless pronta

    falta = conta && falta(conta, pronta)
    return [texto(:"pronta_#{falta}", passo: id, consulta: nome(pronta))] if falta

    sem_entrada(id, pronta, passo['fonte']['entradas'].to_h) + dados_de_fora(id, pronta, Array(passo['guardar']))
  end

  def sem_entrada(id, pronta, entradas)
    pronta.entradas.reject { |entrada| Array(entradas[entrada]).any? }
          .map { |entrada| texto(:pronta_sem_entrada, passo: id, consulta: nome(pronta), entrada: rotulo_da_entrada(pronta, entrada)) }
  end

  def dados_de_fora(id, pronta, guardar)
    guardar.reject { |dado| pronta.caminhos.include?(dado['caminho']) }
           .map { |dado| texto(:pronta_dado_desconhecido, passo: id, consulta: nome(pronta), nome: dado['nome']) }
  end

  # Os `$valor` das entradas, para a régua da Receita.
  def caminhos_lidos(fonte) = fonte.to_h['entradas'].to_h.values.flat_map { |partes| ::Autonomia::Automacao::Texto.caminhos(partes) }

  # Cada entrada montada com os valores do alvo: { 'cep' => '01310-100' }. A vazia vem nil (o passo não busca).
  def entradas_montadas(fonte, valores)
    fonte.to_h['entradas'].to_h.transform_values { |partes| ::Autonomia::Automacao::Texto.new(partes, valores).montar&.strip.presence }
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.consulta.#{chave}", **valores)
end
