require 'rails_helper'

# A GUARDA DA ENTREGA 6: saída de recusa nova que não deixe registro REPROVA A SUÍTE.
#
# A varredura de 10/09/2026 achou onze saídas de recusa onde a memória dizia "são duas" — e um
# revisor achou mais uma que a minha primeira varredura, fixa em cinco arquivos, não via
# (`Native::Base#error`). Uma lista escrita à mão envelhece no dia seguinte; o que não envelhece é
# a varredura virar teste, RECURSIVA sobre tudo que é do agente (`VarreduraDeRecusas`).
#
# Três regras:
#   1. Nenhum `{ error: ... }` montado fora de `Tools::Recusa` — nem `.to_json`/`JSON.generate` de
#      hash com `error` em arquivo nenhum, nem hash solto, `h['error'] = x` ou `Hash[...]` nas pastas
#      de ferramenta. Quem precisa recusar chama `Recusa.para_modelo` ou `Bound#recusar`.
#   2. Todo código de recusa escrito no código — literal, CONSTANTE de texto do mesmo arquivo ou o
#      lado direito de um `||`, como primeiro argumento de `recusar`, `registrar`, `para_modelo`,
#      `recusa`, `conferencia`, ou um `return 'codigo'` em `bound.rb` — está em `MOTIVOS`: tem a
#      frase em português e um gatilho em `recusa_registro_spec`.
#
# O QUE FICA DE FORA, de propósito: o texto que uma ferramenta SÍNCRONA devolve DEPOIS de rodar
# ("Não encontrei essa regra nas condições gerais…", "A corretora ainda não conectou…") é resultado,
# não recusa de executar — a recusa ANTES de rodar ("Informe a seguradora…") entra, via
# `Native::Base#recusar`; e os desfechos do job (`prazo_esgotado`, `tool_failed`…) ficam gravados na
# linha `tool_runs`, com conversa, agente e código — outro canal, já existente.
#   3. A varredura enxerga o que já existe. Um visitador quebrado devolveria lista vazia e o teste
#      passaria elogiando o silêncio; aqui ele reprova.
#
# PROVA POR MUTAÇÃO (10/09/2026): um `{ error: 'x' }.to_json` ou `{ 'error' => 'x' }` a mais em
# `bound.rb` reprova a regra 1 com arquivo e linha; um `return 'motivo_novo'` em `async_refusal`
# reprova a 2.
RSpec.describe Autonomia::Agents::Tools::Recusa do
  let(:varredura) { VarreduraDeRecusas }
  # Abaixo disto a varredura não está enxergando o código de 10/09/2026 (eram 26 saídas).
  let(:minimo_conhecido) { 22 }

  describe 'guarda estática (entrega 6)' do
    it 'regra 1: nenhum { error: ... } montado fora do produtor unico' do
      fora = varredura.arquivos.reject { |caminho| caminho == varredura::PRODUTOR_UNICO }
                      .flat_map { |caminho| varredura.produtores_de_erro(caminho) }

      expect(fora).to be_empty,
                      "saída de recusa sem registro — troque por Recusa.para_modelo / Bound#recusar:\n#{fora.join("\n")}"
    end

    it 'regra 1 (autoteste): o visitador enxerga o Hash do produtor unico, e so ele' do
      expect(varredura.produtores_de_erro(varredura::PRODUTOR_UNICO).size).to eq(1)
    end

    it 'regra 2: todo codigo de recusa escrito no codigo tem frase no catalogo' do
      fora = varredura.saidas.select(&:codigo).reject { |saida| described_class::MOTIVOS.key?(saida.codigo) }

      expect(fora).to be_empty, "código de recusa fora de MOTIVOS (sem frase e sem exemplo):\n#{fora.join("\n")}"
    end

    it 'regra 3 (autoteste): a varredura enxerga as saidas que existem' do
      saidas = varredura.saidas

      expect(saidas.size).to be >= minimo_conhecido
      expect(saidas.map(&:id)).to include('bound.rb#execute#1', 'bound.rb#async_refusal#2', 'insurance_quote.rb#start#2',
                                          'async_run_job.rb#registrar_recusa#1', 'insurance_capabilities.rb#call#1')
      expect(saidas.map(&:id).uniq.size).to eq(saidas.size)
    end
  end
end
