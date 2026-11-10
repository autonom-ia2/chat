# O passo "webhook" (G13, #2670, F8.4): manda os campos escolhidos a outro sistema (n8n, ERP, seguradora, cobrança) e
# usa a resposta dele. O envio, a segurança e a assinatura moram no EnvioDoWebhook; o segredo, no SegredoDoWebhook.
#
# - O corpo é o do valor calculado (G16): `{"cnpj": {"$valor": "card.atributos.cnpj"}}`. Valor vazio pula o passo,
#   como na ação: nada sai pela metade.
# - `gravar` leva chaves da resposta JSON para atributos do card, do contato ou da conversa (`{"chave": "numero",
#   "destino": "card.atributos.numero_cliente"}`). A chave com ponto lê dentro do objeto (`cliente.id`). Grava pela
#   porta da ação, como quem ligou, e só valor simples (texto, número, sim/não). Vale também na recusa: é assim que o
#   motivo que o outro sistema mandou chega ao aviso do ramo `se_recusar`.
# - 2xx segue. 4xx é recusa: com `se_recusar`, entra nele; sem ele, a execução para com o motivo. 5xx, 408, 429 e falta
#   de resposta são passageiros: o motor tenta de novo (3 vezes, 1 e 5 minutos) e depois para. Endereço recusado e
#   redirecionamento param na hora, sem tentar de novo.
# - O registro guarda o host, o código, a duração e as chaves gravadas. Nunca a URL inteira, o corpo, a resposta nem o
#   segredo: o histórico é lido por quem tem a chave de automações, e o repositório é público.
class Autonomia::Automacao::PassoDeWebhook
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  RAMO = 'se_recusar'.freeze
  PASSAGEIROS = [408, 425, 429].freeze
  # Onde a resposta pode gravar, e a ação da plataforma que grava em cada lugar.
  DESTINOS = {
    'card.atributos' => ['PATCH crm/cards/:id', :card],
    'contato.atributos' => ['PATCH contacts/:id', :contato],
    'conversa.atributos' => ['POST conversations/:id/custom_attributes', :conversa]
  }.freeze

  # Ao salvar: o motor de gatilhos ligado, quem salva pode mandar dados para fora, o endereço, os valores lidos no corpo
  # (pelo bloco de quem confere a receita) e cada destino um atributo que a conta tem, num lugar que o gatilho alcança
  # (o mesmo bloco, com `:caminho`: é onde a ação grava, e na automação de conversa o card dela é só para ler, #2716).
  # `account_user` nil (o catálogo, a leitura sem pessoa) não confere a pessoa.
  def self.problemas_ao_salvar(conta, passo, account_user, &)
    id = passo['id']
    desligado = ::Autonomia::Automacao::Motor.gatilhos_sem_crm?(conta) ? [] : [frase(:webhook_desligado, passo: id)]
    desligado += [frase(:webhook_sem_permissao, passo: id)] unless account_user.nil? || pode_mandar?(account_user)
    endereco = ::Autonomia::Automacao::EnvioDoWebhook.problema_do_endereco(passo['url'])
    corpo = ::Autonomia::Automacao::Corpo
    lidos = corpo.caminhos(passo['corpo'].to_h).flat_map(&) +
            corpo.formas_desconhecidas(passo['corpo'].to_h).map { |chave| frase(:forma_desconhecida, chave: chave) }
    desligado + Array(endereco && frase(endereco, passo: id)) + lidos + destinos(passo, &)
  end

  # Mandar dados da conta para outro sistema é integração: o administrador, ou a função com `integration_manage` (regra
  # de delegação do CLAUDE.md, #2027). `automation_manage` sozinha monta a automação, mas não manda nada para fora.
  def self.pode_mandar?(account_user) = account_user.permission_granted?(CHAVE)

  CHAVE = 'integration_manage'.freeze
  # Texto da resposta gravado num atributo: até aqui (a resposta pode ter até 64 KB).
  TEXTO_MAXIMO = 255

  def self.destinos(passo, &)
    gravar = Array(passo['gravar'])
    repetidos = gravar.pluck('destino').tally.select { |_destino, vezes| vezes > 1 }.keys
    chaves_ruins(passo) + gravar.flat_map { |item| destino(passo['id'], item['destino'], &) } +
      repetidos.map { |destino| frase(:webhook_destino_repetido, passo: passo['id'], destino: destino) }
  end

  # "cliente.numero" entra no objeto; ponto no começo, no fim ou dobrado não aponta para nada.
  def self.chaves_ruins(passo)
    Array(passo['gravar']).pluck('chave').select { |chave| chave.to_s.split('.', -1).any?(&:empty?) }
                          .map { |chave| frase(:webhook_chave_invalida, passo: passo['id'], chave: chave) }
  end

  def self.destino(id, destino)
    valido = DESTINOS.keys.any? { |prefixo| destino.to_s.start_with?("#{prefixo}.") }
    return [frase(:webhook_destino_invalido, passo: id, destino: destino)] unless valido

    yield destino, :caminho
  end

  def self.frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
  end

  def executar
    return pulado('webhook_desligado') unless ::Autonomia::Automacao::Motor.gatilhos_sem_crm?(@execucao.account)
    # Quem ligou perdeu a chave de integrações: pausa a automação, como a ação sem permissão.
    return Resultado.new(tipo: :sem_acesso, motivo: 'webhook_sem_permissao', dados: {}) unless ainda_pode_mandar?

    montado = ::Autonomia::Automacao::Corpo.new(@passo['corpo'].to_h, valores: @valores, conta: @execucao.account).montar
    return pulado(montado.motivo) if montado.motivo

    desfecho(envio(montado.corpo).enviar)
  end

  private

  def envio(corpo)
    ::Autonomia::Automacao::EnvioDoWebhook.new(url: @passo['url'], corpo: corpo, execucao_id: @execucao.id, passo_id: @passo['id'],
                                               segredo: ::Autonomia::Automacao::SegredoDoWebhook.new(@execucao.automacao).valor)
  end

  def desfecho(resposta)
    dados = { 'host' => resposta.host, 'codigo' => resposta.codigo, 'ms' => resposta.ms }.compact
    return Resultado.new(tipo: :permanente, motivo: resposta.motivo, dados: dados) if resposta.tipo == :recusado_aqui
    return Resultado.new(tipo: :passageiro, motivo: 'webhook_sem_resposta', dados: dados) if passageiro?(resposta)
    return Resultado.new(tipo: :permanente, motivo: 'webhook_redirecionou', dados: dados) if resposta.codigo.between?(300, 399)
    return recusa(resposta, dados) unless resposta.codigo.between?(200, 299)

    depois_do_envio(gravar(lido(resposta.corpo)), dados, resposta.motivo)
  end

  # O outro sistema já recebeu: daqui em diante nada é passageiro, senão o motor mandaria de novo. A gravação que falhar
  # para a execução com o motivo (o que já foi gravado fica).
  def depois_do_envio(gravado, dados, motivo)
    dados = dados.merge(gravado.dados)
    return Resultado.new(tipo: :ok, motivo: motivo, dados: dados) if gravado.tipo == :ok
    return Resultado.new(tipo: :sem_acesso, motivo: gravado.motivo, dados: dados) if gravado.tipo == :sem_acesso

    Resultado.new(tipo: :permanente, motivo: 'webhook_gravar_falhou', dados: dados)
  end

  def passageiro?(resposta)
    resposta.tipo == :sem_resposta || resposta.codigo.nil? || resposta.codigo >= 500 || PASSAGEIROS.include?(resposta.codigo)
  end

  # 4xx: o outro sistema disse não. Com o ramo, grava o que a resposta trouxe (o motivo, para o aviso) e segue por ele;
  # sem o ramo, nada do texto de quem recusou entra na conta, e a execução para.
  def recusa(resposta, dados)
    return Resultado.new(tipo: :permanente, motivo: 'webhook_recusado', dados: dados) if Array(@passo[RAMO]).empty?

    gravado = depois_do_envio(gravar(lido(resposta.corpo)), dados, 'webhook_recusado')
    gravado.tipo == :ok ? Resultado.new(tipo: :ok, motivo: 'webhook_recusado', dados: gravado.dados.merge('ramo' => RAMO)) : gravado
  end

  # A resposta como objeto JSON; outra coisa (texto, lista, vazio) não tem o que gravar.
  def lido(texto)
    objeto = texto.present? ? JSON.parse(texto) : nil
    objeto.is_a?(Hash) ? objeto : {}
  rescue JSON::ParserError
    {}
  end

  # Uma ação por lugar (card, contato, conversa), como no extrair. A primeira recusa interrompe as seguintes.
  def gravar(resposta)
    achados = achados_na(resposta)
    ausentes = Array(@passo['gravar']).pluck('chave') - achados.map { |item, _valor| item['chave'] }
    com_lugar, sem_lugar = achados.partition { |item, _valor| dono_do(base_do(item['destino'])) }
    recusa, gravados = gravar_por_lugar(com_lugar)
    dados = registro(gravados, ausentes, sem_lugar)
    recusa ? Resultado.new(tipo: recusa.tipo, motivo: recusa.motivo, dados: dados) : Resultado.new(tipo: :ok, dados: dados)
  end

  # [a recusa ou nil, as chaves gravadas]: a primeira recusa interrompe os lugares seguintes.
  def gravar_por_lugar(achados)
    gravados = []
    pedidos(achados).each do |acao, id, corpo, chaves|
      resultado = ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo_da_acao(acao, id, corpo), valores: nil,
                                                          acesso: @acesso).executar
      return [resultado, gravados] unless resultado.tipo == :ok

      gravados.concat(chaves)
    end
    [nil, gravados]
  end

  # [item, valor] de cada chave que a resposta trouxe com valor simples.
  def achados_na(resposta)
    Array(@passo['gravar']).filter_map do |item|
      valor = valor_na(resposta, item['chave'])
      [item, valor.is_a?(String) ? valor.truncate(TEXTO_MAXIMO) : valor] if simples?(valor)
    end
  end

  # A chave com ponto entra no objeto; o caminho que passa por um valor que não é objeto não acha nada.
  def valor_na(resposta, chave)
    chave.to_s.split('.').reduce(resposta) { |atual, parte| atual.is_a?(Hash) ? atual[parte] : nil }
  end

  # Relida a cada envio: a chave tirada no meio da execução vale já para o próximo passo, como em AcoesDoMotor.
  def ainda_pode_mandar?
    conta = @acesso.account_user&.reload
    conta.present? && self.class.pode_mandar?(conta)
  rescue ActiveRecord::RecordNotFound
    false
  end

  def simples?(valor) = valor.is_a?(String) || valor.is_a?(Numeric) || [true, false].include?(valor)

  # `sem_lugar`: as chaves que a resposta trouxe para um lugar que o alvo não tem (o card sem conversa). Não gravam, e o
  # histórico diz quais, em vez de sumirem.
  def registro(gravados, ausentes, sem_lugar)
    { 'gravados' => gravados, 'ausentes' => ausentes,
      'sem_lugar' => sem_lugar.map { |item, _valor| item['chave'] }.presence }.compact
  end

  # O card, o contato ou a conversa do alvo onde a base grava; nil quando o alvo não tem esse lugar.
  def dono_do(base) = contexto.public_send(DESTINOS.fetch(base).last)

  # [ação, id, corpo, chaves] por lugar, só dos lugares que o alvo tem.
  def pedidos(achados)
    achados.group_by { |item, _valor| base_do(item['destino']) }.map do |base, lista|
      acao, lugar = DESTINOS.fetch(base)
      dono = dono_do(base)
      atributos = lista.to_h.transform_keys { |item| item['destino'].delete_prefix("#{base}.") }
      [acao, lugar == :conversa ? dono.display_id : dono.id, corpo_do_lugar(lugar, atributos), lista.map { |item, _valor| item['chave'] }]
    end
  end

  def base_do(destino) = DESTINOS.keys.find { |prefixo| destino.to_s.start_with?("#{prefixo}.") }

  def corpo_do_lugar(lugar, atributos)
    lugar == :conversa ? { 'custom_attributes' => atributos, 'merge' => true } : { 'custom_attributes' => atributos }
  end

  def passo_da_acao(acao, id, corpo)
    { 'id' => @passo['id'], 'acao' => acao, 'descricao' => I18n.t('autonomia.automacao.webhook.gravar'), 'caminho' => { 'id' => id },
      'corpo' => corpo }
  end

  def contexto = (@contexto ||= ::Autonomia::Automacao::Contexto.de(@execucao.alvo))

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})
end
