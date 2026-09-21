// @vitest-environment node
// A trava do Guia no Pull Request (#535) roda no CI, em Node.
import {
  ROTULO_DISPENSA,
  MARCA_DO_COMENTARIO,
  motivoDaDispensa,
  decidir,
  comentarioDaTrava,
} from '../trava.mjs';

const tela = nome => ({
  nome,
  caminho: `/app/accounts/:accountId/${nome}`,
  papeis: ['administrator'],
  flag: null,
});

describe('o motivo da dispensa, no corpo do PR', () => {
  it('lê o motivo escrito depois da marca', () => {
    const corpo =
      'Muda a tela de ajuda.\n\nGuia não se aplica: tela interna de depuração\n';

    expect(motivoDaDispensa(corpo)).toBe('tela interna de depuração');
  });

  it('não depende de maiúscula na marca', () => {
    expect(motivoDaDispensa('GUIA NÃO SE APLICA: só para suporte')).toBe(
      'só para suporte'
    );
  });

  // Marca sem texto depois é um jeito de desligar a trava sem deixar rastro.
  it('não aceita a marca sem motivo nenhum', () => {
    expect(motivoDaDispensa('Guia não se aplica:   ')).toBeNull();
  });

  it('não acha motivo onde não há a marca', () => {
    expect(motivoDaDispensa('Este PR não mexe no Guia.')).toBeNull();
    expect(motivoDaDispensa(null)).toBeNull();
  });
});

describe('a decisão da trava', () => {
  it('libera o PR que não cria tela sem explicação', () => {
    expect(decidir({ novas: [], rotulos: [], corpo: '' })).toEqual({
      bloqueia: false,
      situacao: 'em_dia',
    });
  });

  // O motivo de a trava existir.
  it('barra o PR que cria tela sem explicação', () => {
    expect(
      decidir({ novas: [tela('crm_relatorios')], rotulos: [], corpo: '' })
    ).toEqual({ bloqueia: true, situacao: 'sem_explicacao' });
  });

  it('libera com o rótulo de dispensa e o motivo escrito', () => {
    expect(
      decidir({
        novas: [tela('debug_interno')],
        rotulos: ['bug', ROTULO_DISPENSA],
        corpo: 'Guia não se aplica: tela só de depuração',
      })
    ).toEqual({
      bloqueia: false,
      situacao: 'dispensada',
      motivo: 'tela só de depuração',
    });
  });

  // Só o rótulo, sem motivo, é um botão de desligar a trava.
  it('continua barrando com o rótulo mas sem o motivo', () => {
    expect(
      decidir({
        novas: [tela('debug_interno')],
        rotulos: [ROTULO_DISPENSA],
        corpo: 'Ajustes gerais.',
      })
    ).toEqual({ bloqueia: true, situacao: 'dispensa_sem_motivo' });
  });

  // O motivo sozinho, sem o rótulo, não dispensa: a dispensa é uma decisão
  // explícita de quem abre o PR, não um efeito colateral de uma frase no texto.
  it('não dispensa só pela frase no corpo, sem o rótulo', () => {
    expect(
      decidir({
        novas: [tela('debug_interno')],
        rotulos: [],
        corpo: 'Guia não se aplica: tela só de depuração',
      }).bloqueia
    ).toBe(true);
  });
});

describe('o comentário no PR', () => {
  // A marca é como o workflow acha o comentário para atualizar em vez de
  // empilhar um novo a cada push.
  it('sempre leva a marca que o workflow procura', () => {
    const comentario = comentarioDaTrava({
      decisao: { situacao: 'em_dia', bloqueia: false },
      rascunhos: [],
    });

    expect(comentario.startsWith(MARCA_DO_COMENTARIO)).toBe(true);
  });

  it('traz o rascunho de cada tela e as três saídas', () => {
    const comentario = comentarioDaTrava({
      decisao: { situacao: 'sem_explicacao', bloqueia: true },
      rascunhos: [
        {
          tela: tela('crm_relatorios'),
          rascunho: {
            titulo: 'Relatórios do CRM',
            onde_fica: 'CRM > Relatórios',
            duvidas: 'não sei se agente comum vê',
          },
        },
      ],
    });

    expect(comentario).toContain('### crm_relatorios');
    expect(comentario).toContain('- titulo: Relatórios do CRM');
    expect(comentario).toContain('não sei se agente comum vê');
    expect(comentario).toContain('_fora_do_guia');
    expect(comentario).toContain(ROTULO_DISPENSA);
  });

  // A IA fora do ar não libera a trava — e quem lê o PR precisa saber por que
  // não veio rascunho.
  it('diz por que não veio rascunho quando a IA falhou', () => {
    const comentario = comentarioDaTrava({
      decisao: { situacao: 'sem_explicacao', bloqueia: true },
      rascunhos: [
        { tela: tela('crm_relatorios'), erro: 'a OpenAI recusou (HTTP 500)' },
      ],
    });

    expect(comentario).toContain('Sem rascunho:');
    expect(comentario).toContain('HTTP 500');
  });

  it('pede o motivo quando o rótulo veio sem ele', () => {
    const comentario = comentarioDaTrava({
      decisao: { situacao: 'dispensa_sem_motivo', bloqueia: true },
      rascunhos: [],
    });

    expect(comentario).toContain('Guia não se aplica: <motivo>');
  });
});
