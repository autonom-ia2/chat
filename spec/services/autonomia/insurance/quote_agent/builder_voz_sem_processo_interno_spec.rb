require 'rails_helper'

# PROCESSO INTERNO NÃO CHEGA AO CLIENTE (prova real de 18/09/2026, conversa 5045 da conta 16). A Lia disse
# "novas tentativas podem gerar custo" e "não consegui confirmar a abertura da cotação". A primeira vinha do
# manual do especialista, que dava o custo como motivo sem dizer que ele é nosso; a segunda, da descrição do
# papel `incerto`, que falava em cotação "aberta". A promessa sobre a equipe não muda aqui: fica para a
# integração com o handoff do CRM.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:instrucoes) { Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES }
  let(:principal) { instrucoes.join('principal.md').read }
  # O MANUAL MONTADO (#525): as duas frases que este exemplo guarda moraram no arquivo de auto até
  # 20/09/2026 e passaram para o bloco comum, onde valem para qualquer ramo. Lendo só o arquivo de
  # auto, a guarda sumiria junto com o texto.
  let(:especialista) { described_class.instrucao_do_especialista('especialista_auto.md') }
  let(:descricoes) { Autonomia::Agents::Tools::Native::InsuranceQuote::Frases::DESCRICOES }

  it 'os dois manuais proíbem falar de custo, tentativa, abertura, sistema e processo interno' do
    expect(principal[/## 4\. Como você fala.*?(?=\n## \d)/m])
      .to include('Não fale de custo, de tentativa, de "abertura" da', 'cotação, de "sistema" nem de como a corretora trabalha por dentro.')
    expect(especialista).to include('**Processo interno não chega ao cliente**',
                                    'nada de custo, de tentativa, de "abertura" da cotação, de "sistema"')
    expect(especialista).to include('cada tentativa custa, e esse motivo é nosso, nunca do cliente.')
    expect(especialista).not_to include('cotação foi consumida')
  end

  # O CLIENTE NUNCA OUVE FALAR DE ESPECIALISTA (decisão do CEO em 20/09/2026, #547). Na conversa 6983 a Lia
  # escreveu "vou passar para o especialista de seguro auto": o especialista é engrenagem nossa, e quem fala
  # com o cliente é ela. A guarda na fala (`ConferenciaDaFala::VOCABULARIO_INTERNO`) pede a reescrita; esta
  # linha tira o vocabulário da origem, inclusive da frase que a §6 dava de exemplo ao cliente.
  it 'o manual do principal diz que o cliente nunca ouve falar de especialista' do
    expect(principal[/## 4\. Como você fala.*?(?=\n## \d)/m])
      .to include('O cliente nunca ouve falar de especialista')
    expect(principal).not_to include('Posso pedir para um especialista entrar')
  end

  it 'as descrições dos desfechos falhou e incerto não carregam vocabulário interno e mantêm o atendente' do
    %i[falhou incerto].each do |papel|
      expect(descricoes[papel]).not_to match(/abert|sistema|tentativ|custo|conclu/i)
      expect(descricoes[papel]).to include('um atendente vai')
    end
  end
end
