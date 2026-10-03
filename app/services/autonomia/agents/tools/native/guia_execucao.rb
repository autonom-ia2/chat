# O Guia FAZENDO a mudança na conta (issue #855).
#
# Antes (#568) toda mudança era só proposta, uma por turno, com o Confirmar na
# tela. Pedido de verdade quase sempre tem várias etapas, e o Guia caía num
# passo a passo para a pessoa fazer na mão: em 02/10/2026, na conta 18, "deixa
# esses agentes só nesta caixa" exigia criar a função, aplicá-la e ajustar a
# caixa — e virou um tutorial de seis itens.
#
# Agora ele executa, passo a passo, e devolve o que a plataforma respondeu —
# inclusive o id do que criou, para o passo seguinte usar. O que protege é o
# desfazer: cada linha que muda fica anotada por 5 dias. O que não tem volta
# (`Acoes::SEM_DESFAZER`) não passa por aqui: vai para `propor_acao`.
class Autonomia::Agents::Tools::Native::GuiaExecucao < Autonomia::Agents::Tools::Native::Base
  # O que volta da plataforma para o modelo. Pequeno: ele precisa do id e dos
  # campos principais do que mudou, não do registro inteiro.
  TETO = 2_000

  class << self
    def slug
      'executar_acao'
    end

    def description
      'Faz uma mudança na conta AGORA (criar, alterar, apagar), com a permissão de quem pediu. Tudo o que ' \
        'você fizer pode ser desfeito pela pessoa por 5 dias. Chame uma vez por passo, na ordem: o retorno ' \
        'traz o que a plataforma respondeu, inclusive o id do que foi criado, para usar no passo seguinte. ' \
        'Só funciona para quem administra a conta.'
    end

    def params
      [
        { 'name' => 'acao', 'type' => 'string',
          'description' => 'A ação, em linguagem de rota: "POST crm/pipelines", "PATCH inboxes/:id", ' \
                           '"DELETE labels/:id".' },
        { 'name' => 'descricao', 'type' => 'string',
          'description' => 'UMA frase curta, no idioma da pessoa, dizendo o que este passo fez — é o que ela ' \
                           'lê na lista do que você fez. Nunca suavize: apagar se diz apagar.' },
        { 'name' => 'caminho_json', 'type' => 'string', 'required' => false,
          'description' => 'Preenche os ":id" da rota, como objeto JSON: {"id":"12"}.' },
        { 'name' => 'corpo_json', 'type' => 'string', 'required' => false,
          'description' => 'Os campos a gravar, como objeto JSON: {"name":"Comercial"}. Use os nomes de ' \
                           'campo da própria plataforma.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    acao = @params['acao'].to_s
    return sem_volta(acao) unless @operador.acoes.desfazivel?(acao)

    dados = { caminho: objeto('caminho_json'), corpo: objeto('corpo_json'), descricao: @params['descricao'].to_s }
    nao_lidos = @operador.nao_lidos(dados[:caminho])
    return sem_leitura(nao_lidos) if nao_lidos.any?

    feito(@operador.executar(acao, dados))
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    "#{e.message}#{vizinhas}"
  end

  private

  # O retorno da plataforma conta como leitura: o id do que acabou de ser
  # criado pode ser usado no passo seguinte sem ler a conta de novo.
  def feito(resultado)
    return "Não foi feito: #{resultado.mensagem}" unless resultado.ok

    corpo = ::Autonomia::Guide::Resumo.new(corpo: resultado.corpo.to_s, teto: TETO).texto
    @operador.lido(corpo) if corpo.start_with?('[', '{')
    "Feito. A plataforma respondeu: #{corpo}"
  end

  def sem_volta(acao)
    "Não executei: \"#{acao}\" não tem desfazer (sai da plataforma ou troca credencial). Use propor_acao, " \
      'para a pessoa confirmar na tela antes.'
  end

  def vizinhas
    recurso = @params['acao'].to_s.split(' ', 2).last.to_s
    return '' if recurso.blank?

    base = recurso.split('/').first
    existentes = @operador.acoes.catalogo.select { |acao| acao.split(' ', 2).last.to_s.start_with?(base) }
    return '' if existentes.blank?

    " Para isto, o que existe é: #{existentes.join(', ')}."
  end

  def objeto(nome)
    texto = @params[nome].to_s.strip
    return {} if texto.blank?

    valores = JSON.parse(texto)
    valores.is_a?(Hash) ? valores.deep_symbolize_keys : {}
  rescue JSON::ParserError
    {}
  end

  def sem_leitura(nao_lidos)
    "Não executei: #{nao_lidos.map { |nome, valor| "#{nome} #{valor}" }.join(', ')} não veio de nenhuma " \
      'leitura da conta nem de um passo anterior nesta conversa. Leia a conta, ache o registro pelo nome que a ' \
      'pessoa disse e use o id que veio; se houver mais de um, pergunte qual; se não houver, diga que não existe.'
  end

  def recusa_sem_contexto
    'Não consigo mudar a conta agora porque não sei quem está pedindo. Explique como a pessoa faz na tela.'
  end
end
