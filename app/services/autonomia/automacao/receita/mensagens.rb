# "mensagem", "avisar" e "email" ao salvar (F4, G2; #2608, saiu da Receita): só com a flag da F4, os valores do texto
# (do assunto do e-mail e de cada variável do modelo da Meta, F4b) lidos da lista fechada, os times e as pessoas do
# aviso da própria conta, o modelo pronto na conta e a caixa do e-mail uma caixa de e-mail da conta. A versão 2 da mensagem
# (#3099, DuasVersoes) passa pela mesma régua, com as regras próprias dela.
class Autonomia::Automacao::Receita::Mensagens
  include ::Autonomia::Automacao::Receita::Frase

  # `contexto`: Receita::Contexto. `leitura`: a régua dos valores (Receita::Leitura).
  def initialize(contexto, leitura)
    @conta = contexto.conta
    @alvo = contexto.alvo
    @leitura = leitura
  end

  def problemas(passo)
    id = passo['id']
    desligado = ::Autonomia::Automacao::Motor.mensagens?(@conta) ? [] : [texto(:passo_desligado, passo: id)]
    textos = [passo['texto'], passo['assunto'], *Array(passo.dig('modelo', 'variaveis')), *da_segunda_versao(passo)]
    lidos = textos.flat_map { |partes| ::Autonomia::Automacao::Texto.caminhos(partes) }.flat_map(&no_texto(id))
    caixa = passo['tipo'] == 'email' ? ::Autonomia::Automacao::PassoDeEmail.problemas_ao_salvar(@conta, passo) : []
    desligado + lidos + destinatarios_de_fora(passo) + modelos(passo) + caixa + ::Autonomia::Automacao::DuasVersoes.problemas_ao_salvar(passo)
  end

  private

  attr_reader :alvo

  # O modelo da Meta (F4b) e, com duas versões (#3099), o da versão 2: cada um pronto na conta.
  def modelos(passo)
    [passo['modelo'], passo.dig('versoes', 'modelo')].compact.uniq.flat_map do |modelo|
      ::Autonomia::Automacao::ModeloWhatsapp.problemas_ao_salvar(@conta, passo['id'], modelo)
    end
  end

  # #3099: o texto e as variáveis do modelo da versão 2 passam pela mesma régua da versão 1.
  def da_segunda_versao(passo)
    return [] unless ::Autonomia::Automacao::DuasVersoes.do_passo?(passo)

    [passo.dig('versoes', 'texto'), *Array(passo.dig('versoes', 'modelo', 'variaveis'))]
  end

  def destinatarios_de_fora(passo)
    ::Autonomia::Automacao::DestinatariosDoAviso.new(@conta, alvo).problemas(passo['id'], passo['para'])
  end

  # A conferência do caminho que vai para um texto (mensagem, aviso, e-mail, retorno).
  def no_texto(id) = ->(caminho) { @leitura.problemas(id, caminho, onde: :texto) }
end
