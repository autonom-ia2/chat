# #3099: o passo "mensagem" com duas versões no executor (Executor#passo_nativo, via DuasVersoes.classe_do). Escolhe a
# versão do alvo (a vencedora, se já houver; senão o sorteio fixo) e manda pelo PassoDeMensagem de sempre, com o texto e
# o modelo da versão. Tudo o que vale para a mensagem vale igual: janela, modelo, contato que não recebe, número novo,
# robô do outro lado.
#
# Só o envio que saiu conta para o teste: grava a linha em autonomia_automacao_versoes_envios e põe `versao` no registro
# do passo (o histórico mostra qual versão a pessoa recebeu). O que pulou ou parou não conta.
class Autonomia::Automacao::DuasVersoes::Envio
  DuasVersoes = ::Autonomia::Automacao::DuasVersoes

  def initialize(execucao:, passo:, alvo:)
    @execucao = execucao
    @passo = passo
    @alvo = alvo
  end

  def executar
    versao = versao_do_alvo
    resultado = ::Autonomia::Automacao::PassoDeMensagem.new(execucao: @execucao, passo: DuasVersoes.passo_da_versao(@passo, versao),
                                                            alvo: @alvo).executar
    return resultado unless resultado.tipo == :ok

    registrar!(versao)
    resultado.class.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.merge('versao' => versao))
  end

  private

  def versao_do_alvo
    DuasVersoes.teste_de(@execucao.automacao, @passo['id']).vencedora || DuasVersoes.sorteio(@execucao.automacao_id, @passo, @alvo)
  end

  def registrar!(versao)
    ::Autonomia::Automacao::VersaoEnvio.create!(
      account_id: @execucao.account_id, automacao_id: @execucao.automacao_id, passo: @passo['id'], execucao_id: @execucao.id,
      alvo_type: @alvo.class.polymorphic_name, alvo_id: @alvo.id, contact_id: contato&.id, versao: versao
    )
  end

  def contato = ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao).contato
end
