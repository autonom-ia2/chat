# A receita de uma automação (#2414 F3, ADR-001 2.1 e 2.3). O formato mora no esquema
# (lib/operator_guide/automacao-receita.schema.json), que o Versao confere pelo JsonSchemaValidator. Aqui fica o que o
# esquema não sabe dizer, conferido ao salvar:
# - o id de cada passo é único na receita inteira (o cursor da execução aponta para ele);
# - a ação está na lista de permitidas (F3.2) e tem todo parâmetro do caminho;
# - o corpo bate com o formato da ação, como no Guia, e traz o que a automação exige (F3.10), os campos fixos e
#   nenhum campo proibido;
# - o valor calculado no corpo (G16: `$valor`, `$texto`, `$data`) lê caminhos que a automação sabe ler, e a data parte
#   de "hoje" ou de um atributo do tipo data;
# - todo `$valor` do caminho, do corpo e das condições é um caminho que a automação sabe ler;
# - a condição sobre um valor fechado (`mensagem.tipo`) usa uma das opções e um dos operadores dele (#2496);
# - o gatilho de card só com a flag da F6, e a etapa ou o funil escolhidos nele são da conta (#2499);
# - o "esperar até" sem prazo não tem passos em "se vencer", que nunca rodariam (#2750);
# - o "decidir" a cada resposta (G31/G46) repete caminhos dele e deixa um para seguir (DecidirDeNovo);
# - o que o "esperar até" faz enquanto espera (G63, G64): a hora da conferência só sem prazo, o galho "a cada mensagem"
#   só com cliente e fora de outro galho (EnquantoEspera).
class Autonomia::Automacao::Receita
  ESQUEMA = JSON.parse(Rails.root.join('lib/operator_guide/automacao-receita.schema.json').read).freeze
  # `passos`: o ramo do "em outro registro" (G18, #2671), que roda numa execução filha, no registro ligado. `se_recusar`:
  # o do "webhook" (G13), quando o outro sistema recusa.
  RAMOS = %w[entao senao se_vencer a_cada_mensagem se_recusar passos].freeze
  # O "decidir" (F7, #2500) abre um ramo por caminho (`caminhos[].passos`) e o de "nenhum se aplica" (`nenhum`).
  NENHUM = 'nenhum'.freeze
  # Os passos de IA (F7), só com a flag da F7.
  IA = %w[decidir extrair escrever resumir].freeze
  # G70: o campo do card no extrair nunca é o que guarda gente: a pessoa da equipe (G62) e o contato da conta (decisão
  # 16, a âncora do "em outro registro"). A IA não escolhe gente (Receita::PassosDeIa, PassoDeExtrair).
  CAMPOS_DE_GENTE = %w[pessoa contato].freeze

  include ::Autonomia::Automacao::Receita::Frase
  # O passo "ação" ao salvar (AcaoNaReceita): a ação da lista, o caminho e o corpo.
  include ::Autonomia::Automacao::AcaoNaReceita

  # As listas de passos que um passo abre, na ordem em que aparecem. É a única travessia da receita: o salvar, o ligar, a
  # chave de funis (sem_funil? do controller) e o Roteiro andam por aqui. Um ramo que ficasse de fora deixaria a ação
  # dentro dele sem conferência.
  def self.ramos(passo)
    caminhos = Array(passo['caminhos']).map { |caminho| caminho['passos'] if caminho.is_a?(Hash) }
    [*RAMOS.map { |ramo| passo[ramo] }, *caminhos, passo[NENHUM]].select { |lista| lista.is_a?(Array) }
  end

  # O JsonSchemaValidator põe o erro na chave de dentro (`gatilho`), não em `receita`; quem segue para a conferência
  # do código pergunta aqui.
  def self.esquema_valido?(receita)
    @esquema ||= JSONSchemer.schema(ESQUEMA)
    @esquema.valid?(JSON.parse(receita.to_json))
  end

  # `account_user`: quem salva ou liga, na conta. Com ele, o valor que pede permissão (Valores::PROTEGIDOS, #2597) só
  # entra se ele pode ler; `nil` explícito (o catálogo, a leitura sem pessoa) não aplica a regra aqui, e a execução
  # continua lendo vazio. Obrigatório, sem padrão: quem monta a Receita diz quem é, e o esquecimento quebra o spec.
  # `alvo`: o tipo do registro em que a receita roda, quando não é o do gatilho: o ramo do "em outro registro" (G18) é
  # conferido como uma receita própria, no registro ligado (EmOutroRegistro.problemas_ao_salvar). `origem`: nesse ramo, o
  # tipo do alvo do gatilho da mãe, que o ramo lê com `origem.*` (G65); fora dele, nil e `origem.*` é recusado.
  def initialize(receita, conta:, account_user:, alvo: nil, origem: nil)
    @receita = receita
    @conta = conta
    @account_user = account_user
    @alvo = alvo
    @origem = origem
  end

  # Frases para a pessoa (ou o Guia) corrigir. Vazio = pode salvar. Só roda com a receita já no esquema.
  def problemas
    [*(@alvo ? [] : ids_repetidos), *gatilho.problemas,
     *do_alvo.flat_map { |passo| problemas_do_passo(passo) },
     *::Autonomia::Automacao::Duracao.sem_prazo_que_vence(do_alvo).map { |id| texto(:sem_prazo_com_se_vencer, passo: id) },
     *::Autonomia::Automacao::EnquantoEspera.problemas_ao_salvar(@receita, do_alvo, alvo)]
  end

  # Todos os passos, inclusive os de dentro dos ramos, na ordem em que aparecem.
  def passos(lista = @receita['passos'])
    Array(lista).flat_map { |passo| [passo, *self.class.ramos(passo).flat_map { |ramo| passos(ramo) }] }
  end

  # Os passos que rodam no alvo desta receita, na mesma execução: o ramo do "em outro registro" roda numa execução filha,
  # no registro ligado, e é conferido lá. O texto da IA (#2679) também só passa entre passos da mesma execução.
  def do_alvo(lista = @receita['passos']) = Array(lista).flat_map { |passo| [passo, *ramos_do_alvo(passo).flat_map { |ramo| do_alvo(ramo) }] }

  def ramos_do_alvo(passo) = ::Autonomia::Automacao::EmOutroRegistro.do_tipo?(passo) ? [] : self.class.ramos(passo)

  private

  def ids_repetidos = passos.pluck('id').tally.select { |_id, vezes| vezes > 1 }.keys.map { |id| texto(:id_repetido, passo: id) }

  def problemas_do_passo(passo)
    return condicoes.problemas(passo['id'], passo['condicao'], na_espera: passo['tipo'] == 'esperar_ate') if passo.key?('condicao')
    return mensagens.problemas(passo) if %w[mensagem avisar email].include?(passo['tipo'])
    return passos_de_ia.problemas(passo) if IA.include?(passo['tipo'])
    return passos_proprios.problemas(passo) if ::Autonomia::Automacao::PassosProprios.do_tipo?(passo)
    return [] unless passo['tipo'] == 'acao'

    problemas_da_acao(passo)
  end

  # Os passos com conferência própria (PassosProprios); os caminhos que eles leem passam pela régua daqui.
  def passos_proprios
    @passos_proprios ||= ::Autonomia::Automacao::PassosProprios.new(conta: @conta, account_user: @account_user, receita: @receita,
                                                                    alvo: alvo, dentro: @alvo.present?) do |id, c, **opcoes|
                                                                      problemas_do_caminho(id, c, **opcoes)
                                                                    end
  end

  # A régua dos valores (Leitura): a ação, os passos próprios e os textos perguntam aqui.
  def problemas_do_caminho(...) = leitura.problemas(...)

  def leitura = @leitura ||= ::Autonomia::Automacao::Receita::Leitura.new(self, contexto)

  def condicoes = @condicoes ||= ::Autonomia::Automacao::Receita::Condicoes.new(leitura)

  def mensagens = @mensagens ||= ::Autonomia::Automacao::Receita::Mensagens.new(contexto, leitura)

  def passos_de_ia = @passos_de_ia ||= ::Autonomia::Automacao::Receita::PassosDeIa.new(contexto)

  def gatilho = ::Autonomia::Automacao::Receita::Gatilho.new(self, contexto, condicoes)

  # O que os validadores recebem (Receita::Contexto).
  def contexto
    @contexto ||= ::Autonomia::Automacao::Receita::Contexto.new(receita: @receita, conta: @conta, account_user: @account_user,
                                                                alvo: alvo, origem: @origem)
  end

  # O tipo do registro em que a receita roda: o do ramo do "em outro registro" (G18), ou o do gatilho.
  def alvo = @alvo || ::Autonomia::Automacao::Gatilhos.alvo(@receita.dig('gatilho', 'tipo'))
end
