require 'rails_helper'

# PROCESSO INTERNO NÃO CHEGA AO CLIENTE (prova real de 18/09/2026, conversa 5045 da conta 16). A Lia disse
# "novas tentativas podem gerar custo" e "não consegui confirmar a abertura da cotação". A primeira vinha do
# manual do especialista, que dava o custo como motivo sem dizer que ele é nosso; a segunda, da descrição do
# papel `incerto`, que falava em cotação "aberta". A promessa sobre a equipe não muda aqui: fica para a
# integração com o handoff do CRM.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:instrucoes) { Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES }
  let(:principal) { instrucoes.join('principal.md').read }
  let(:especialista) { instrucoes.join('especialista_auto.md').read }
  let(:descricoes) { Autonomia::Agents::Tools::Native::InsuranceQuote::Frases::DESCRICOES }

  it 'os dois manuais proíbem falar de custo, tentativa, abertura, sistema e processo interno' do
    expect(principal[/## 4\. Como você fala.*?(?=\n## \d)/m])
      .to include('Não fale de custo, de tentativa, de "abertura" da', 'cotação, de "sistema" nem de como a corretora trabalha por dentro.')
    expect(especialista).to include('**Processo interno não chega ao cliente**',
                                    'nada de custo, de tentativa, de "abertura" da cotação, de "sistema"')
    expect(especialista).to include('cada tentativa custa, e esse motivo é nosso, nunca do cliente.')
    expect(especialista).not_to include('cotação foi consumida')
  end

  it 'as descrições dos desfechos falhou e incerto não carregam vocabulário interno e mantêm o atendente' do
    %i[falhou incerto].each do |papel|
      expect(descricoes[papel]).not_to match(/abert|sistema|tentativ|custo|conclu/i)
      expect(descricoes[papel]).to include('um atendente vai')
    end
  end
end
