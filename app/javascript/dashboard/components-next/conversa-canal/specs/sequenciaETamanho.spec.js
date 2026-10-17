import { continuaASequencia } from '../useSequenciaDaConversa';
import {
  extensaoDoArquivo,
  nomeDoArquivo,
  resumoDoArquivo,
  tamanhoDoArquivo,
} from '../midia/tamanhoDoArquivo';

const FUSO = 'America/Sao_Paulo';
// 16/10/2026 15:00 em São Paulo.
const BASE = Date.UTC(2026, 9, 16, 18, 0) / 1000;
const mensagem = (extras = {}) => ({
  messageType: 0,
  senderId: 7,
  createdAt: BASE,
  status: 'sent',
  ...extras,
});

describe('continuaASequencia (#1702)', () => {
  it('a mesma pessoa no mesmo dia continua, mesmo minutos depois', () => {
    const anterior = mensagem();
    const atual = mensagem({ createdAt: BASE + 25 * 60 });
    expect(continuaASequencia(anterior, atual, FUSO)).toBe(true);
  });

  it('troca de lado, de atendente ou de dia abre sequência nova', () => {
    const cliente = mensagem();
    const empresa = mensagem({ messageType: 1, senderId: 1 });
    expect(continuaASequencia(cliente, empresa, FUSO)).toBe(false);
    expect(
      continuaASequencia(
        empresa,
        mensagem({ messageType: 1, senderId: 2 }),
        FUSO
      )
    ).toBe(false);
    const outroDia = mensagem({ createdAt: BASE + 12 * 3600 });
    expect(continuaASequencia(cliente, outroDia, FUSO)).toBe(false);
  });

  it('modelo continua a sequência da empresa; nota e aviso não', () => {
    const empresa = mensagem({ messageType: 1, senderId: 1 });
    const modelo = mensagem({ messageType: 3, senderId: 1 });
    expect(continuaASequencia(empresa, modelo, FUSO)).toBe(true);
    const nota = mensagem({ messageType: 1, senderId: 1, private: true });
    expect(continuaASequencia(empresa, nota, FUSO)).toBe(false);
    const aviso = mensagem({ messageType: 2, senderId: 1 });
    expect(continuaASequencia(aviso, aviso, FUSO)).toBe(false);
  });

  it('atendente e robô com o mesmo id são pessoas diferentes', () => {
    const ana = mensagem({ messageType: 1, senderId: 1, senderType: 'User' });
    const robo = mensagem({
      messageType: 1,
      senderId: 1,
      senderType: 'AgentBot',
    });
    expect(continuaASequencia(ana, robo, FUSO)).toBe(false);
  });

  it('mensagem que falhou abre sequência', () => {
    expect(
      continuaASequencia(mensagem(), mensagem({ status: 'failed' }), FUSO)
    ).toBe(false);
  });
});

describe('tamanhoDoArquivo (#1702)', () => {
  it('KB arredondado e MB com uma casa abaixo de 10', () => {
    expect(tamanhoDoArquivo(109568)).toBe('107 KB');
    expect(tamanhoDoArquivo(300)).toBe('1 KB');
    expect(tamanhoDoArquivo(6 * 1024 * 1024)).toBe('6 MB');
    expect(tamanhoDoArquivo(2.5 * 1024 * 1024)).toBe('2,5 MB');
    expect(tamanhoDoArquivo(12.4 * 1024 * 1024)).toBe('12 MB');
    expect(tamanhoDoArquivo(1048575)).toBe('1 MB');
    expect(tamanhoDoArquivo(0)).toBe('');
  });

  it('nome, extensão e resumo do cartão', () => {
    const anexo = {
      dataUrl: 'https://x.test/rails/blobs/abc/Proposta%20final.pdf',
      fileSize: 109568,
    };
    expect(nomeDoArquivo(anexo)).toBe('Proposta final.pdf');
    expect(extensaoDoArquivo(anexo)).toBe('PDF');
    expect(resumoDoArquivo(anexo)).toBe('PDF • 107 KB');
    expect(extensaoDoArquivo({ extension: '.mp4' })).toBe('MP4');
    expect(resumoDoArquivo({ dataUrl: 'https://x.test/semtipo' })).toBe('');
  });
});
