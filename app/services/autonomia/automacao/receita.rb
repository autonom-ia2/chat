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
# - o "esperar até" sem prazo não tem passos em "se vencer", que nunca rodariam (#2750).
# - o "decidir" a cada resposta (G31) só repete caminhos dele, sem passos, e deixa um para seguir (DecidirDeNovo).
class Autonomia::Automacao::Receita
  ESQUEMA = JSON.parse(Rails.root.join('lib/operator_guide/automacao-receita.schema.json').read).freeze
  RAMOS = %w[entao senao se_vencer].freeze
  # O "decidir" (F7, #2500) abre um ramo por caminho (`caminhos[].passos`) e o de "nenhum se aplica" (`nenhum`).
  NENHUM = 'nenhum'.freeze
  # Os passos de IA (F7), só com a flag da F7.
  IA = %w[decidir extrair escrever resumir].freeze
  # Onde o extrair pode gravar, além dos atributos do contato e da conversa (`<base>.atributos.<chave>`).
  DESTINOS_FIXOS = %w[contato.nome empresa.nome].freeze
  DESTINOS_DE_ATRIBUTO = %w[contato.atributos conversa.atributos].freeze
  # A chave do caminho sai do nome (minúscula, sem acento) e precisa de pelo menos uma letra.
  LETRAS = ('a'..'z')

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
  def initialize(receita, conta:, account_user:)
    @receita = receita
    @conta = conta
    @account_user = account_user
  end

  # Frases para a pessoa (ou o Guia) corrigir. Vazio = pode salvar. Só roda com a receita já no esquema.
  def problemas
    [*ids_repetidos, *gatilho_novo, *conversa_nova, *filtros_do_gatilho, *passos.flat_map { |passo| problemas_do_passo(passo) },
     *::Autonomia::Automacao::Duracao.sem_prazo_que_vence(passos).map { |id| texto(:sem_prazo_com_se_vencer, passo: id) }]
  end

  # Todos os passos, inclusive os de dentro dos ramos, na ordem em que aparecem.
  def passos(lista = @receita['passos'])
    Array(lista).flat_map { |passo| [passo, *self.class.ramos(passo).flat_map { |ramo| passos(ramo) }] }
  end

  private

  def ids_repetidos
    passos.pluck('id').tally.select { |_id, vezes| vezes > 1 }.keys.map { |id| texto(:id_repetido, passo: id) }
  end

  # O gatilho de card e o de tempo (#2499): a flag, a etapa, o funil e o campo de data são da conta; no da conta (G7),
  # os passos que ele aceita.
  def gatilho_novo
    ::Autonomia::Automacao::ProblemasDoGatilho.new(@receita['gatilho'].to_h, @conta, passos: passos, account_user: @account_user).problemas
  end

  # A caixa por onde abrir a conversa de quem não tem (#2680): da conta, e quem salva pode começar conversa nela.
  def conversa_nova = ::Autonomia::Automacao::ConversaNova.problemas_ao_salvar(@conta, @receita['gatilho'].to_h, @account_user)

  def filtros_do_gatilho
    Array(@receita.dig('gatilho', 'filtros')).flat_map { |condicao| problemas_da_condicao('gatilho', condicao, no_gatilho: true) }
  end

  def problemas_do_passo(passo)
    return problemas_da_condicao(passo['id'], passo['condicao'], na_espera: passo['tipo'] == 'esperar_ate') if passo.key?('condicao')
    return problemas_da_mensagem(passo) if %w[mensagem avisar email].include?(passo['tipo'])
    return problemas_da_ia(passo) if IA.include?(passo['tipo'])
    return problemas_do_retorno(passo) if passo['tipo'] == 'retorno'
    return problemas_do_proprio_passo(passo) if %w[ia_assumir card campanha].include?(passo['tipo'])
    return [] unless passo['tipo'] == 'acao'

    problemas_da_acao(passo)
  end

  # Os passos que se conferem sozinhos ao salvar, na própria classe: o "Passar para a agente de IA" (G15), o "criar
  # card" (G4), que confere também a pessoa, e a campanha (G14), que confere o gatilho, a pessoa e a campanha da tela.
  def problemas_do_proprio_passo(passo)
    case passo['tipo']
    when 'card' then ::Autonomia::Automacao::PassoDeCard.problemas_ao_salvar(@conta, passo, @account_user)
    when 'campanha'
      ::Autonomia::Automacao::PassoDeCampanha.problemas_ao_salvar(passo, @receita, conta: @conta, account_user: @account_user)
    else ::Autonomia::Automacao::PassoDeIaAssumir.problemas_ao_salvar(@conta, passo)
    end
  end

  # "mensagem", "avisar" e "email" (F4, G2): só com a flag da F4, os valores do texto (do assunto do e-mail e de cada
  # variável do modelo da Meta, F4b) lidos da lista fechada, os times e as pessoas do aviso da própria conta, o modelo
  # pronto na conta e a caixa do e-mail uma caixa de e-mail da conta.
  def problemas_da_mensagem(passo)
    id = passo['id']
    desligado = ::Autonomia::Automacao::Motor.mensagens?(@conta) ? [] : [texto(:passo_desligado, passo: id)]
    textos = [passo['texto'], passo['assunto'], *Array(passo.dig('modelo', 'variaveis'))]
    lidos = textos.flat_map { |partes| ::Autonomia::Automacao::Texto.caminhos(partes) }.flat_map(&no_texto(id))
    caixa = passo['tipo'] == 'email' ? ::Autonomia::Automacao::PassoDeEmail.problemas_ao_salvar(@conta, passo) : []
    modelo = ::Autonomia::Automacao::ModeloWhatsapp.problemas_ao_salvar(@conta, id, passo['modelo'])
    desligado + lidos + destinatarios_de_fora(passo) + modelo + caixa
  end

  # Passos de IA (F7): só com a flag da F7; o que fala com gente (escrever ao cliente, resumir avisando) também com a da
  # F4. Os caminhos e os campos não repetem, e o extrair só grava onde pode.
  def problemas_da_ia(passo)
    id = passo['id']
    [*(::Autonomia::Automacao::Motor.ia?(@conta) ? [] : [texto(:ia_desligada, passo: id)]),
     *(fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta) ? [texto(:passo_desligado, passo: id)] : []),
     *caminhos_repetidos(id, Array(passo['caminhos'])),
     *caminhos_sem_chave_boa(id, Array(passo['caminhos'])),
     *::Autonomia::Automacao::DecidirDeNovo.problemas_ao_salvar(passo),
     *repetidos(id, Array(passo['campos']).pluck('chave'), :campo_repetido),
     *Array(passo['campos']).flat_map { |campo| destino_invalido(id, campo['destino']) },
     *destinatarios_de_fora('id' => id, 'para' => avisar_do_resumir(passo))]
  end

  # "criar retorno" (G3): a conferência mora no PassoDeRetorno; os caminhos lidos, pela régua daqui.
  def problemas_do_retorno(passo)
    ::Autonomia::Automacao::PassoDeRetorno.problemas_ao_salvar(@conta, passo, @receita, @account_user, &no_texto(passo['id']))
  end

  # O destino do resumir é "nota" (texto) ou { avisar: ... }; o do escrever é sempre texto.
  def avisar_do_resumir(passo) = passo['destino'].is_a?(Hash) ? passo['destino']['avisar'] : nil

  def fala_com_gente?(passo)
    (passo['tipo'] == 'escrever' && passo['destino'] == 'mensagem') || (passo['tipo'] == 'resumir' && passo['destino'].is_a?(Hash))
  end

  # Dois caminhos com a mesma chave ("Cotação" e "cotacao" viram cotacao) ou com o mesmo nome à vista (quem chama a API
  # pode mandar chaves diferentes): uma frase por grupo, com o nome do primeiro, que é o que a pessoa vê.
  def caminhos_repetidos(id, caminhos)
    primeiros = caminhos.each_index.filter_map do |indice|
      caminhos.first(indice).index { |outro| mesmo_caminho?(outro, caminhos[indice]) }
    end
    primeiros.uniq.map { |indice| texto(:caminho_repetido, passo: id, nome: caminhos[indice]['nome']) }
  end

  def mesmo_caminho?(primeiro, outro) = primeiro['chave'] == outro['chave'] || nome_comparavel(primeiro) == nome_comparavel(outro)

  def nome_comparavel(caminho) = caminho['nome'].to_s.strip.downcase

  # A chave "nenhum" é do ramo "nenhum se aplica": um caminho com ela deixaria a resposta da IA e o histórico ambíguos.
  # E a chave precisa de letra: "!!!" vira vazia e "123" fica só com dígitos.
  def caminhos_sem_chave_boa(id, caminhos)
    caminhos.filter_map do |caminho|
      chave = caminho['chave'].to_s
      next texto(:caminho_reservado, passo: id, nome: caminho['nome']) if chave == NENHUM

      texto(:caminho_sem_letra, passo: id, nome: caminho['nome']) if chave.each_char.none? { |letra| LETRAS.cover?(letra) }
    end
  end

  def repetidos(id, chaves, motivo)
    chaves.tally.select { |_chave, vezes| vezes > 1 }.keys.map { |chave| texto(motivo, passo: id, chave: chave) }
  end

  def destino_invalido(id, destino)
    base = DESTINOS_DE_ATRIBUTO.find { |prefixo| destino.to_s.start_with?("#{prefixo}.") }
    valido = DESTINOS_FIXOS.include?(destino) ||
             (base && destino.to_s.length > base.length + 1 && ::Autonomia::Automacao::Valores.atributo_definido?(destino, @conta))
    valido ? [] : [texto(:destino_invalido, passo: id, destino: destino)]
  end

  def destinatarios_de_fora(passo)
    ::Autonomia::Automacao::DestinatariosDoAviso.new(@conta, @receita.dig('gatilho', 'tipo')).problemas(passo['id'], passo['para'])
  end

  # O caminho que não vale ali já diz o que corrigir; o valor fora só aparece depois.
  def problemas_da_condicao(id, condicao, no_gatilho: false, na_espera: false)
    lidos = ::Autonomia::Automacao::Condicao.caminhos(condicao).flat_map do |caminho|
      problemas_do_caminho(id, caminho, no_gatilho: no_gatilho, na_espera: na_espera)
    end
    lidos.presence || fora_do_fechado(id, condicao)
  end

  # Operador ou valor que um valor fechado não tem: a condição nunca casaria.
  def fora_do_fechado(id, condicao)
    filhas = condicao.values_at('todas', 'alguma').compact.flatten
    return filhas.flat_map { |filha| fora_do_fechado(id, filha) } unless condicao.key?('campo')

    caminho = condicao.dig('campo', '$valor')
    fechado = ::Autonomia::Automacao::Valores.fechado(caminho)
    return [] unless fechado
    return [texto(:operador_fora, passo: id, caminho: caminho, operadores: fechado['operadores'].join(', '))] unless
      fechado['operadores'].include?(condicao['op'])
    return [] if fechado['opcoes'].include?(condicao['valor'])

    [texto(:valor_fora, passo: id, caminho: caminho, valor: condicao['valor'], opcoes: fechado['opcoes'].join(', '))]
  end

  # Caminho que a automação não sabe ler, ou atributo que a conta não tem. O atributo apagado depois de salvar chega
  # vazio no motor, com o motivo no registro. A resposta (G11) só existe na condição do "esperar até": fora dele não há
  # o começo da espera, e ela leria sempre vazio. O texto da IA (#2679) só vem de um passo que escreve. A mensagem que
  # falhou (G53) não vale no "Só se" do gatilho (`no_gatilho`): a Partida filtra sem ela. `onde`: :caminho ou :corpo da
  # ação, :texto (mensagem, aviso, e-mail, retorno); nil é o que decide (filtro e condição). Na ação, a automação de
  # conversa não usa o card para agir (#2716): nenhum `card.*` no caminho e nenhum `card.id` no corpo; copiar um campo
  # do card é ler.
  def problemas_do_caminho(id, caminho, no_gatilho: false, na_espera: false, onde: nil)
    valores = ::Autonomia::Automacao::Valores
    return [texto(:valor_desconhecido, passo: id, caminho: caminho)] unless valores.caminho_valido?(caminho)
    return ::Autonomia::Automacao::TextoDaIaNaReceita.new(self, @receita).problemas(id, caminho, no_gatilho: no_gatilho) if valores.da_ia?(caminho)

    fora = valores.fora_do_lugar(caminho, mensagem: mensagem_no_gatilho?(no_gatilho), na_espera: na_espera,
                                          gatilho: @receita.dig('gatilho', 'tipo'), no_filtro: no_gatilho)
    return [texto(fora, passo: id, caminho: caminho)] if fora
    return [texto(:valor_fora_do_alvo, passo: id, caminho: caminho)] unless no_alvo_do_gatilho?(caminho)

    no_lugar = ::Autonomia::Automacao::CardDaConversa.problema(caminho, onde, @receita.dig('gatilho', 'tipo'))
    return [texto(no_lugar, passo: id, caminho: caminho)] if no_lugar

    Array(valores.problema_de_leitura(caminho, conta: @conta, account_user: @account_user)).map { |chave| texto(chave, passo: id, caminho: caminho) }
  end

  # #2499: `card.*` num gatilho de conversa não tem de onde ler. Gatilho desconhecido o esquema já recusou.
  # A conversa nova (#2680) dá ao alvo sem conversa (o contato) a ponte para a que ela abre.
  def no_alvo_do_gatilho?(caminho)
    alvo = ::Autonomia::Automacao::Gatilhos.alvo(@receita.dig('gatilho', 'tipo'))
    return true if alvo.nil? || ::Autonomia::Automacao::Valores.no_alvo?(caminho, alvo)

    ::Autonomia::Automacao::ConversaNova.caixa_id(@receita).present? && caminho.to_s.start_with?('conversa.')
  end

  # A conferência do caminho que vai para um texto (mensagem, aviso, e-mail, retorno).
  def no_texto(id) = ->(caminho) { problemas_do_caminho(id, caminho, onde: :texto) }

  def mensagem_no_gatilho?(no_gatilho) = no_gatilho && @receita.dig('gatilho', 'tipo') == ::Autonomia::Automacao::Valores::GATILHO_DA_MENSAGEM

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
