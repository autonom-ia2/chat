import { QUEM_COTA, quemCotaNaConta } from '../../carteira/ajustesDaRenovacao';
import {
  COTACAO,
  cotacaoDoCard,
  cotaEsteSeguro,
  respostasEmGrupos,
} from '../../carteira/cotacaoDoCard';
import {
  dadosEscritos,
  primeiroDadoQueFalta,
} from '../../carteira/dadosQueFaltam';
import { PASSOS, passoDaVez } from '../../carteira/passoDaVez';
import { periodoDoPreco } from '../../carteira/periodoDoPreco';
import { variacaoDaProposta } from '../../carteira/situacaoDoSeguro';
import { tituloDaRenovacao } from '../../carteira/tituloDaRenovacao';

// As regras puras da onda 5 (#2897): o passo da vez (o único botão azul), a
// lista do que falta para cotar, quem não recebe, o período do preço e quem
// faz a cotação.
const pessoa = {
  phone_number: '+55 11 90000-0001',
  opted_out_at: null,
  blocked: false,
};
const proposta = { valor: 100, variacao: 5 };
const seguro = (renovacao, quem = pessoa, tipo = 'auto') => ({
  renovacao,
  pessoa: quem,
  tipo,
});

describe('passoDaVez: um botão azul por vez, o do passo que falta', () => {
  const noComeco = { etapa: 'A vencer' };

  it.each([
    [COTACAO.NAO_COMECOU, PASSOS.COTAR_AGORA],
    [COTACAO.DEMOROU, PASSOS.COTAR_DE_NOVO],
    [COTACAO.FALHOU, PASSOS.COTAR_DE_NOVO],
    [COTACAO.AGGER_FORA, PASSOS.ENTRAR_NO_AGGER],
    [COTACAO.FALTOU_SEM_AGENTE, PASSOS.COTAR_COM_DADOS],
    [COTACAO.NAO_COTA, PASSOS.ANEXAR_PROPOSTA],
    [COTACAO.PRONTA, PASSOS.ENVIAR],
    [COTACAO.PRECO_SEM_PDF, PASSOS.ENVIAR_RESUMO],
    [COTACAO.SEM_TELEFONE, PASSOS.POR_TELEFONE],
    [COTACAO.NAO_QUER, PASSOS.CONVERSAR],
    [COTACAO.BLOQUEADO, PASSOS.CONVERSAR],
    [COTACAO.NAO_SAIU, PASSOS.CONVERSAR],
    [COTACAO.ENVIADA_SOZINHA, PASSOS.RENOVOU],
    [COTACAO.ENVIADA_POR_VOCE, PASSOS.RENOVOU],
    [COTACAO.ENVIADA_POR, PASSOS.RENOVOU],
  ])('cotação %s -> %s', (cotacao, esperado) => {
    expect(passoDaVez(noComeco, cotacao)).toEqual({ id: esperado });
  });

  it('enquanto cota, ou enquanto o agente espera a resposta, não há passo: nenhum botão azul', () => {
    expect(passoDaVez(noComeco, COTACAO.COTANDO)).toBeNull();
    expect(passoDaVez(noComeco, COTACAO.FALTOU_PERGUNTADO)).toBeNull();
  });

  it('quem resolve preencher os dados sem esperar a resposta ganha "Cotar com estes dados"', () => {
    expect(
      passoDaVez(noComeco, COTACAO.FALTOU_PERGUNTADO, { preenchendo: true })
    ).toEqual({ id: PASSOS.COTAR_COM_DADOS });
  });

  it('algumas seguradoras responderam: o passo é pedir a proposta da de menor preço que tem proposta', () => {
    const respostas = [
      { nome: 'Cara', valor: 900 },
      { nome: 'Sem proposta', valor: 500, semPdf: true },
      { nome: 'Em conta', valor: 700 },
      { nome: 'Calada', valor: null },
      { nome: 'Recusou', valor: null, recusou: 'nao_aceita_este_carro' },
    ];

    expect(passoDaVez({ ...noComeco, respostas }, COTACAO.PARCIAL)).toEqual({
      id: PASSOS.PEDIR_PROPOSTA,
      seguradora: 'Em conta',
    });
    // Ninguém respondeu ainda: não há o que pedir.
    expect(
      passoDaVez(
        { ...noComeco, respostas: [{ nome: 'Calada', valor: null }] },
        COTACAO.PARCIAL
      )
    ).toBeNull();
  });

  it('renovação terminada ou sem cotação não tem passo', () => {
    expect(passoDaVez({ etapa: 'Renovado' }, null)).toBeNull();
    expect(passoDaVez(null, null)).toBeNull();
    expect(
      passoDaVez({ etapa: 'Cotando', desfecho: 'nao_renovou' }, null)
    ).toBeNull();
  });
});

describe('o que falta para cotar é uma lista', () => {
  it('lista vazia não é "faltou"; com lista, depende de alguém já ter perguntado', () => {
    expect(
      cotacaoDoCard(seguro({ etapa: 'A vencer', faltou: [] }), {
        cotaSozinha: true,
      })
    ).toBe(COTACAO.NAO_COMECOU);
    expect(
      cotacaoDoCard(
        seguro({
          etapa: 'A vencer',
          faltou: ['placa', 'nascimento'],
          perguntou: 'Nina',
        })
      )
    ).toBe(COTACAO.FALTOU_PERGUNTADO);
    expect(
      cotacaoDoCard(seguro({ etapa: 'A vencer', faltou: ['placa'] }))
    ).toBe(COTACAO.FALTOU_SEM_AGENTE);
  });

  it('o título diz "Falta um dado" com um e "Faltam dados" com mais de um', () => {
    const um = { etapa: 'A vencer', faltou: ['nascimento'] };
    const varios = { etapa: 'A vencer', faltou: ['placa', 'nascimento'] };

    expect(tituloDaRenovacao(um, COTACAO.FALTOU_SEM_AGENTE)).toEqual({
      id: 'FALTA_UM_DADO',
    });
    expect(tituloDaRenovacao(varios, COTACAO.FALTOU_SEM_AGENTE)).toEqual({
      id: 'FALTAM_DADOS',
    });
    expect(tituloDaRenovacao(varios, COTACAO.FALTOU_PERGUNTADO)).toEqual({
      id: 'FALTAM_DADOS',
    });
  });

  it('diz qual é o primeiro dado vazio (espaço não conta) e devolve os escritos sem as sobras', () => {
    const faltou = ['placa', 'nascimento', 'estado_civil'];
    const escritos = { placa: ' FIC-0B10 ', nascimento: '   ' };

    expect(primeiroDadoQueFalta(faltou, escritos)).toBe('nascimento');
    expect(primeiroDadoQueFalta(faltou, {})).toBe('placa');
    expect(
      primeiroDadoQueFalta(faltou, {
        placa: 'FIC-0B10',
        nascimento: '12/03/1988',
        estado_civil: 'casada',
      })
    ).toBeNull();
    expect(dadosEscritos(['placa'], { ...escritos, outro: 'x' })).toEqual({
      placa: 'FIC-0B10',
    });
    // Nada do que chega é alterado.
    expect(escritos.placa).toBe(' FIC-0B10 ');
  });
});

describe('quem não recebe a proposta sozinha', () => {
  const pronta = { etapa: 'Cotando', proposta };
  const bloqueada = { ...pessoa, blocked: true };

  it('pessoa bloqueada: estado próprio, só quando há o que enviar', () => {
    expect(cotacaoDoCard(seguro(pronta, bloqueada))).toBe(COTACAO.BLOQUEADO);
    expect(
      cotacaoDoCard(seguro({ etapa: 'Cotando', cotando: true }, bloqueada))
    ).toBe(COTACAO.COTANDO);
    expect(
      cotacaoDoCard(seguro({ etapa: 'A vencer' }, bloqueada), {
        cotaSozinha: true,
      })
    ).toBe(COTACAO.NAO_COMECOU);
    expect(tituloDaRenovacao(pronta, COTACAO.BLOQUEADO)).toEqual({
      id: 'PRONTA_ENVIE_NA_CONVERSA',
    });
  });

  it('o bloqueio segue a regra de "sem telefone" e "não quer": cada estado da cotação antes de haver o que enviar continua o mesmo', () => {
    const semTelefone = { ...pessoa, phone_number: null };
    const naoQuer = { ...pessoa, opted_out_at: 1 };
    const daConta = { cotaSozinha: true };
    const ANTES_DE_HAVER_O_QUE_ENVIAR = [
      { etapa: 'A vencer' },
      { etapa: 'Cotando', cotando: true },
      { etapa: 'Cotando', respostas: [] },
      { etapa: 'A vencer', parou: 'falhou' },
      { etapa: 'A vencer', faltou: ['placa'] },
    ];
    ANTES_DE_HAVER_O_QUE_ENVIAR.forEach(renovacao => {
      const semImpedimento = cotacaoDoCard(seguro(renovacao), daConta);
      [semTelefone, naoQuer, bloqueada].forEach(quem => {
        expect(cotacaoDoCard(seguro(renovacao, quem), daConta)).toBe(
          semImpedimento
        );
      });
    });
    // Só o preço (sem PDF) também é algo a enviar; o que já saiu continua dito
    // como saiu.
    const soOPreco = { ...pronta, proposta: { ...proposta, semPdf: true } };
    expect(cotacaoDoCard(seguro(soOPreco, bloqueada))).toBe(COTACAO.BLOQUEADO);
    const enviada = {
      etapa: 'Opções enviadas',
      proposta: { ...proposta, enviadaEm: 1, enviadaPor: 'Bia' },
    };
    expect(cotacaoDoCard(seguro(enviada, bloqueada))).toBe(COTACAO.ENVIADA_POR);
  });

  it('sem telefone e "não quer" vêm antes do bloqueio', () => {
    expect(
      cotacaoDoCard(seguro(pronta, { ...bloqueada, phone_number: null }))
    ).toBe(COTACAO.SEM_TELEFONE);
    expect(
      cotacaoDoCard(seguro(pronta, { ...bloqueada, opted_out_at: 1 }))
    ).toBe(COTACAO.NAO_QUER);
  });

  it('a proposta que ia sair sozinha e não saiu tem estado próprio, até alguém enviar', () => {
    const naoSaiu = {
      etapa: 'Cotando',
      proposta: { ...proposta, naoSaiuEm: 10 },
    };

    expect(cotacaoDoCard(seguro(naoSaiu))).toBe(COTACAO.NAO_SAIU);
    expect(tituloDaRenovacao(naoSaiu, COTACAO.NAO_SAIU)).toEqual({
      id: 'PRONTA_NAO_SAIU',
    });
    expect(
      cotacaoDoCard(
        seguro({
          etapa: 'Opções enviadas',
          proposta: { ...naoSaiu.proposta, enviadaEm: 20, enviadaPor: 'Bia' },
        })
      )
    ).toBe(COTACAO.ENVIADA_POR);
  });
});

describe('a conta só cota os tipos que ela cota', () => {
  it('tipo fora da lista cai em "falta a cotação", mesmo com a conta cotando sozinha', () => {
    const daConta = {
      cotaSozinha: true,
      tiposQueCota: ['auto', 'residencial'],
    };
    const noComeco = { etapa: 'A vencer' };

    expect(cotacaoDoCard(seguro(noComeco, pessoa, 'auto'), daConta)).toBe(
      COTACAO.NAO_COMECOU
    );
    expect(cotacaoDoCard(seguro(noComeco, pessoa, 'vida'), daConta)).toBe(
      COTACAO.NAO_COTA
    );
    expect(cotaEsteSeguro({ tipo: 'vida' }, daConta)).toBe(false);
    expect(cotaEsteSeguro({ tipo: 'auto' }, daConta)).toBe(true);
    // Sem lista, vale a chave da conta.
    expect(cotaEsteSeguro({ tipo: 'vida' }, { cotaSozinha: true })).toBe(true);
    expect(cotaEsteSeguro({ tipo: 'auto' }, { cotaSozinha: false })).toBe(
      false
    );
  });
});

describe('as respostas das seguradoras, cada uma no seu grupo', () => {
  it('separa quem deu preço, quem não respondeu, quem recusou e a que está sem senha', () => {
    const respostas = [
      { nome: 'A', valor: 100 },
      { nome: 'B', valor: null },
      { nome: 'C', valor: null, recusou: 'nao_aceita_este_carro' },
      { nome: 'D', valor: null, faltaSenha: true },
    ];

    const grupos = respostasEmGrupos(respostas);

    expect(grupos.deram.map(r => r.nome)).toEqual(['A']);
    expect(grupos.caladas.map(r => r.nome)).toEqual(['B']);
    expect(grupos.recusaram.map(r => r.nome)).toEqual(['C']);
    expect(grupos.semSenha.map(r => r.nome)).toEqual(['D']);
    expect(respostasEmGrupos()).toEqual({
      deram: [],
      caladas: [],
      recusaram: [],
      semSenha: [],
    });
  });
});

describe('o período do preço e a comparação com o ano passado', () => {
  it('"por mês" só quando o dado diz; sem dado, por ano', () => {
    expect(periodoDoPreco({ periodo: 'mes' })).toBe('MES');
    expect(periodoDoPreco({ periodo: 'ano' })).toBe('ANO');
    expect(periodoDoPreco({})).toBe('ANO');
    expect(periodoDoPreco(null)).toBe('ANO');
  });

  it('só compara com o ano passado quando a cobertura é a mesma', () => {
    expect(variacaoDaProposta({ variacao: -3, mesmaCobertura: true })).toEqual({
      id: 'BAIXOU',
      count: 3,
    });
    expect(
      variacaoDaProposta({ variacao: -3, mesmaCobertura: false })
    ).toBeNull();
    expect(variacaoDaProposta({ variacao: 8 })).toBeNull();
  });
});

describe('quem faz a cotação, conforme o que a conta tem', () => {
  it('"Sozinho" só vale na conta que cota sem conversar; senão cai no agente, ou na equipe', () => {
    const cheia = { cotaSemConversa: true, agente: 'Nina' };

    expect(quemCotaNaConta(QUEM_COTA.ROBO, cheia)).toBe(QUEM_COTA.ROBO);
    expect(
      quemCotaNaConta(QUEM_COTA.ROBO, {
        cotaSemConversa: false,
        agente: 'Nina',
      })
    ).toBe(QUEM_COTA.AGENTE);
    expect(
      quemCotaNaConta(QUEM_COTA.ROBO, { cotaSemConversa: false, agente: null })
    ).toBe(QUEM_COTA.NINGUEM);
  });

  it('agente escolhido numa conta sem agente cai em "Sozinho", ou na equipe', () => {
    expect(
      quemCotaNaConta(QUEM_COTA.AGENTE, { cotaSemConversa: true, agente: null })
    ).toBe(QUEM_COTA.ROBO);
    expect(
      quemCotaNaConta(QUEM_COTA.AGENTE, {
        cotaSemConversa: false,
        agente: null,
      })
    ).toBe(QUEM_COTA.NINGUEM);
    expect(
      quemCotaNaConta(QUEM_COTA.NINGUEM, { cotaSemConversa: true, agente: 'N' })
    ).toBe(QUEM_COTA.NINGUEM);
  });
});
