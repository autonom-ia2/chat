import {
  PAUSA_DO_HORARIO,
  cantosDoBalao,
  horarioDoInstagram,
  ladoDaMensagem,
  mensagensDoInstagram,
  sequenciaDoInstagram,
  vistoDaConversa,
} from '../sequenciaDoInstagram';

const RECEBIDA = 0;
const NOSSA = 1;
const t = (chave, valores) =>
  `${valores.dia} de ${valores.mes} de ${valores.ano} ${valores.hora}`;
const msg = (id, messageType, createdAt, extra = {}) => ({
  id,
  messageType,
  createdAt,
  ...extra,
});

describe('sequenciaDoInstagram', () => {
  it('junta as mensagens seguidas do mesmo lado e abre horário só na primeira', () => {
    const lista = [
      msg(1, RECEBIDA, 1000),
      msg(2, RECEBIDA, 1010),
      msg(3, NOSSA, 1020),
      msg(4, NOSSA, 1030),
    ];
    const s = sequenciaDoInstagram(lista);
    expect(s.get(1)).toEqual({
      horario: true,
      comAnterior: false,
      comProxima: true,
    });
    expect(s.get(2)).toEqual({
      horario: false,
      comAnterior: true,
      comProxima: false,
    });
    expect(s.get(3)).toEqual({
      horario: false,
      comAnterior: false,
      comProxima: true,
    });
    expect(s.get(4)).toEqual({
      horario: false,
      comAnterior: true,
      comProxima: false,
    });
  });

  it('a pausa longa abre horário novo e quebra o grupo', () => {
    const lista = [
      msg(1, RECEBIDA, 1000),
      msg(2, RECEBIDA, 1000 + PAUSA_DO_HORARIO + 1),
    ];
    const s = sequenciaDoInstagram(lista);
    expect(s.get(1).comProxima).toBe(false);
    expect(s.get(2)).toEqual({
      horario: true,
      comAnterior: false,
      comProxima: false,
    });
  });

  it('nota privada e atividade ficam fora dos grupos', () => {
    expect(ladoDaMensagem(msg(1, NOSSA, 0, { private: true }))).toBeNull();
    expect(ladoDaMensagem(msg(1, 2, 0))).toBeNull();
    const lista = [
      msg(1, NOSSA, 1000),
      msg(2, NOSSA, 1001, { private: true }),
      msg(3, NOSSA, 1002),
    ];
    const s = sequenciaDoInstagram(lista);
    expect(s.get(1).comProxima).toBe(false);
    expect(s.get(3).comAnterior).toBe(false);
  });
});

describe('cantosDoBalao', () => {
  it('põe 4 px do lado de quem mandou, em cima e embaixo conforme o grupo', () => {
    expect(
      cantosDoBalao({ lado: 'esquerda', comAnterior: false, comProxima: true })
    ).toEqual({ borderRadius: '18px 18px 18px 4px' });
    expect(
      cantosDoBalao({ lado: 'esquerda', comAnterior: true, comProxima: false })
    ).toEqual({ borderRadius: '4px 18px 18px 18px' });
    expect(
      cantosDoBalao({ lado: 'direita', comAnterior: true, comProxima: true })
    ).toEqual({ borderRadius: '18px 4px 4px 18px' });
    expect(
      cantosDoBalao({ lado: 'direita', comAnterior: false, comProxima: false })
    ).toEqual({ borderRadius: '18px 18px 18px 18px' });
  });
});

describe('vistoDaConversa', () => {
  it('marca a última quando é nossa e foi lida', () => {
    expect(
      vistoDaConversa([
        msg(1, RECEBIDA, 1),
        msg(2, NOSSA, 2, { status: 'read' }),
      ])
    ).toBe(2);
  });

  it('não marca quando a última é do cliente ou ainda não foi lida', () => {
    expect(
      vistoDaConversa([
        msg(2, NOSSA, 2, { status: 'read' }),
        msg(3, RECEBIDA, 3),
      ])
    ).toBeNull();
    expect(vistoDaConversa([msg(2, NOSSA, 2, { status: 'sent' })])).toBeNull();
    expect(vistoDaConversa([])).toBeNull();
  });

  it('atividade e nota privada depois da última nossa não tiram o Visto', () => {
    expect(
      vistoDaConversa([
        msg(1, RECEBIDA, 1),
        msg(2, NOSSA, 2, { status: 'read' }),
        msg(3, 2, 3),
        msg(4, NOSSA, 4, { private: true }),
      ])
    ).toBe(2);
  });
});

describe('horarioDoInstagram', () => {
  const fuso = 'America/Sao_Paulo';
  const idioma = 'pt-BR';
  const agora = Date.UTC(2026, 9, 22, 18, 0) / 1000; // 22/10/2026 15:00 em São Paulo

  it('no mesmo dia, só a hora', () => {
    const quando = Date.UTC(2026, 9, 22, 15, 41) / 1000;
    expect(horarioDoInstagram({ quando, agora, fuso, t, idioma })).toBe(
      '12:41'
    );
  });

  it('no mesmo ano, dia e mês curto sem ponto', () => {
    const quando = Date.UTC(2026, 9, 10, 9, 58) / 1000;
    expect(horarioDoInstagram({ quando, agora, fuso, t, idioma })).toBe(
      '10 de out de 2026 06:58'
    );
  });

  it('em outro ano, a data numérica', () => {
    const quando = Date.UTC(2025, 6, 4, 19, 29) / 1000;
    expect(horarioDoInstagram({ quando, agora, fuso, t, idioma })).toBe(
      '04/07/2025 16:29'
    );
  });

  it('usa o fuso da conta, não o do computador', () => {
    const quando = Date.UTC(2026, 9, 23, 2, 30) / 1000; // 22/10 23:30 em São Paulo
    const agoraNoDia = Date.UTC(2026, 9, 23, 2, 40) / 1000;
    expect(
      horarioDoInstagram({ quando, agora: agoraNoDia, fuso, t, idioma })
    ).toBe('23:30');
  });
});

describe('mensagensDoInstagram (#2113)', () => {
  it('tira a linha da reação que o agente da Autonomia leu; o selo já mostra', () => {
    const lista = [
      msg(1, NOSSA, 1000),
      {
        ...msg(2, RECEBIDA, 1010),
        contentAttributes: { autonomiaReaction: { emoji: '❤️' } },
      },
      msg(3, RECEBIDA, 1020),
    ];
    expect(mensagensDoInstagram(lista).map(m => m.id)).toEqual([1, 3]);
  });
});
