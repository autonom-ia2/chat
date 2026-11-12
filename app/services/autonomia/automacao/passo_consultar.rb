# O passo "buscar informação em outro sistema" (#2934): busca (ConsultaDeFora) e guarda os dados escolhidos na execução,
# para os passos seguintes lerem como `consulta.<id do passo>.<chave>`. A chave sai do nome que a pessoa deu ao dado
# (`chave`): minúsculas, sem acento, o resto vira "_", como na tela (passosNovos.js, chaveDoNome).
#
# - Montar e manter pede a chave de integrações (`integration_manage`), como o webhook: buscar dados fora da plataforma é
#   integração. Quem ligou perdeu a chave: pausa a automação.
# - "Onde buscar" é "Outro endereço" (só https). Integração conectada a plataforma ainda não tem para este passo: o
#   salvar recusa `integracao` com a frase, até a primeira existir.
# - Os dados ficam só na execução (Execucao#textos) e somem quando ela termina. O registro guarda os nomes dos dados
#   guardados, a duração e o código; nunca o endereço, o valor nem a resposta: o histórico é lido por quem tem a chave de
#   automações, e o repositório é público.
# - Sem resposta (prazo, erro, endereço interno, resposta sem dados): segue pelo galho `nao_consultou`, se houver; sem ele,
#   pula e segue, e os passos que leem o dado pulam como de costume (valor vazio). Não tenta de novo: o galho é a saída.
class Autonomia::Automacao::PassoConsultar
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  RAMO = 'nao_consultou'.freeze
  ENDERECO = 'endereco'.freeze
  # Onde o passo guarda os dados na execução: "consulta:<id do passo>" => { chave => valor }.
  CHAVE = 'consulta:'.freeze
  TEXTO_MAXIMO = 255
  ACENTOS = (0x300..0x36f)

  # "Status do pedido" => "status_do_pedido". Sem expressão regular: letra por letra.
  def self.chave(nome)
    letras = nome.to_s.unicode_normalize(:nfd).downcase.each_char.reject { |letra| ACENTOS.cover?(letra.ord) }
    letras.map { |letra| letra_ou_numero?(letra) ? letra : '_' }.join.split('_').reject(&:empty?).join('_')
  end

  def self.letra_ou_numero?(letra) = ('a'..'z').cover?(letra) || ('0'..'9').cover?(letra)

  def self.chaves(passo) = Array(passo['guardar']).map { |dado| chave(dado['nome']) }

  # `conferencia`: PassosNovos::Conferencia.
  def self.problemas_ao_salvar(passo, conferencia)
    id = passo['id']
    sem_chave = conferencia.account_user && !::Autonomia::Automacao::PassoDeWebhook.pode_mandar?(conferencia.account_user)
    [*(sem_chave ? [texto(:sem_permissao, passo: id)] : []), *da_fonte(id, passo['fonte'].to_h), *dos_guardados(id, passo)]
  end

  def self.da_fonte(id, fonte)
    return [texto(:integracao_desconhecida, passo: id)] unless fonte['de'] == ENDERECO

    motivo = ::Autonomia::Automacao::ConsultaDeFora.problema_do_endereco(fonte['url'])
    motivo ? [texto(motivo, passo: id)] : []
  end

  # O nome vira a chave do dado: sem letra nem número não há chave, e dois nomes com a mesma chave leriam o mesmo dado.
  # O caminho com ponto no começo, no fim ou dobrado não aponta para nada.
  def self.dos_guardados(id, passo)
    guardar = Array(passo['guardar'])
    sem_letra = guardar.select { |dado| chave(dado['nome']).empty? }.map { |dado| texto(:nome_sem_letra, passo: id, nome: dado['nome']) }
    sem_letra + repetidos(id, passo) + caminhos_invalidos(id, guardar)
  end

  def self.repetidos(id, passo)
    chaves(passo).reject(&:empty?).tally.select { |_chave, vezes| vezes > 1 }.keys.map { |chave| texto(:nome_repetido, passo: id, chave: chave) }
  end

  def self.caminhos_invalidos(id, guardar)
    guardar.pluck('caminho').select { |caminho| caminho.to_s.split('.', -1).any?(&:empty?) }
           .map { |caminho| texto(:caminho_invalido, passo: id, caminho: caminho) }
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.consulta.#{chave}", **valores)

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
  end

  def executar
    return Resultado.new(tipo: :sem_acesso, motivo: 'consulta_sem_permissao', dados: {}) unless ainda_pode?

    @execucao.guardar_texto!("#{CHAVE}#{@passo['id']}", {})
    resposta = ::Autonomia::Automacao::ConsultaDeFora.new(@passo.dig('fonte', 'url')).buscar
    resposta.ok? ? guardar(resposta) : nao_conseguiu(resposta)
  end

  private

  def guardar(resposta)
    lidos = Array(@passo['guardar']).each_with_object({}) do |dado, guardados|
      valor = ::Autonomia::Automacao::ConsultaDeFora.valor_em(resposta.dados, dado['caminho'])
      guardados[self.class.chave(dado['nome'])] = valor.to_s.truncate(TEXTO_MAXIMO) if ::Autonomia::Automacao::ConsultaDeFora.simples?(valor)
    end
    @execucao.guardar_texto!("#{CHAVE}#{@passo['id']}", lidos)
    dados = { 'guardados' => lidos.keys, 'ausentes' => self.class.chaves(@passo) - lidos.keys, 'ms' => resposta.ms }
    Resultado.new(tipo: :ok, motivo: nil, dados: dados.compact_blank)
  end

  def nao_conseguiu(resposta)
    dados = { 'codigo' => resposta.codigo, 'ms' => resposta.ms }.compact
    return Resultado.new(tipo: :pulado, motivo: resposta.motivo, dados: dados) if Array(@passo[RAMO]).empty?

    Resultado.new(tipo: :ok, motivo: resposta.motivo, dados: dados.merge('ramo' => RAMO))
  end

  # Relida a cada busca: a chave tirada no meio da execução vale já para o próximo passo, como no webhook.
  def ainda_pode?
    pessoa = @acesso.account_user&.reload
    pessoa.present? && ::Autonomia::Automacao::PassoDeWebhook.pode_mandar?(pessoa)
  rescue ActiveRecord::RecordNotFound
    false
  end
end
