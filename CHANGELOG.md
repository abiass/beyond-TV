# Changelog

Todas as mudanças relevantes do projeto ficam registradas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e
o projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [0.9.0] — Fase 9: operação remota

### Adicionado

- Captura da tela de cada TV pelo painel. A TV usa `PixelCopy`, que
  inclui sites e vídeos, e a imagem fica só na memória do servidor.
- Menu oculto na TV (⬆⬆⬇⬇ ou OK segurado por 2 s) com informações da
  conexão, do conteúdo, do cache e do log, mais Recarregar e Desparear.
- A TV pode se desparear sozinha (`DELETE /api/v1/device`).
- Log de auditoria de todas as ações que mudam algo, com página própria no
  painel. Nunca grava corpo, parâmetros ou cookies.
- Migração 5 do banco (tabela `audit_log`).

### Alterado

- Desparear a TV também apaga o cache de mídia dela.

### Corrigido

- O app da TV aceitava mal respostas `204` sem corpo.

## [0.8.0] — Fase 8: grupos e agendamento

### Adicionado

- Grupos de TVs, com membros escolhidos em lote e conteúdo padrão. O
  conteúdo próprio da TV tem prioridade sobre o do grupo.
- Agendamentos por dia da semana e faixa de horário, para uma TV ou um
  grupo, com prioridade de 0 a 100. Faixas podem atravessar a meia-noite.
- A TV resolve a agenda no próprio relógio e troca de conteúdo mesmo com
  o servidor fora do ar. Os arquivos de todos os horários são baixados
  com antecedência.
- Telas de grupos e agenda semanal no painel.
- Migração 4 do banco (conteúdo do grupo e tabela `schedules`).

### Alterado

- O servidor só manda `content.sync` para as TVs cujo conteúdo mudou de
  fato.

## [0.7.0] — Fase 7: biblioteca de mídia e playlists

### Adicionado

- Envio de imagens (PNG, JPEG, WebP, GIF, até 25 MiB) e vídeos (MP4,
  WebM, até 500 MiB) pela página Mídia do painel. O servidor confere o
  tipo pelo conteúdo do arquivo e guarda cada um pelo sha256.
- Playlists com sites, imagens e vídeos, montadas num editor de arrastar
  para reordenar, com duração por item.
- Cada TV exibe uma mídia avulsa ou uma playlist. Mudanças na playlist
  chegam às TVs na hora.
- A TV baixa os arquivos com o próprio token, confere o sha256, guarda em
  cache e apaga o que não usa mais. Imagens trocam com transição suave e
  vídeos tocam mudos até o fim.
- Migração 3 do banco (tabelas `playlists` e `playlist_items`).
- Teste de ponta a ponta do servidor com o binário real, cobrindo também
  upload, playlist e download pela TV.

### Corrigido

- O canal ao vivo do painel não abre mais duas conexões quando é iniciado
  duas vezes seguidas.

## [0.6.0] — Fase 6: exibir sites (MVP)

### Adicionado

- Cada TV exibe um site escolhido no painel, em tela cheia, com a tela
  sempre ligada. Só links `http://` e `https://` são aceitos.
- Tela de detalhes da TV no painel: status, dados do aparelho, o que ela
  está exibindo, troca de site (por endereço ou por um site salvo) e os
  botões Recarregar, Identificar e Desparear.
- Identificar mostra o nome da TV em letras grandes por 10 segundos.
- A TV guarda o último conteúdo recebido e continua exibindo se o servidor
  cair.
- Biblioteca de sites (`/api/v1/media`) e migração 2 do banco (tabela
  `media`).

## [0.5.0] — Fase 5: tempo real

### Adicionado

- A TV mantém um WebSocket com o servidor (`/ws/device`), autenticado pelo
  token do pareamento, e manda um sinal de vida a cada 30 segundos.
- Se a conexão cair, a TV tenta de novo com intervalos crescentes, de 1 s
  até 60 s. Depois de 3 falhas ela procura o mesmo servidor na rede, caso o
  IP do PC tenha mudado.
- O painel lista as TVs com status online/offline ao vivo, o que cada uma
  está exibindo e há quanto tempo foi vista (`/ws/admin`).
- Renomear e remover TVs pelo painel. Remover revoga o token na hora e a TV
  volta para a tela de pareamento.
- Rotas `GET`, `PATCH` e `DELETE /api/v1/devices`.

## [0.4.0] — Fase 4: pareamento

### Adicionado

- Botão **Adicionar TV** no painel: gera um código de 6 caracteres válido por
  10 minutos e avisa quando a TV pareia.
- O servidor responde à descoberta por UDP broadcast (porta `8788/udp`,
  configurável com `--discovery-port`).
- `POST /api/v1/pair`: a TV troca o código por um token próprio. Códigos são
  de uso único e cada IP tem 5 tentativas por minuto.
- App da TV: procura servidores na rede, aceita IP manual e tem teclado na
  tela para digitar o código com o controle remoto (D-pad).
- A TV guarda as credenciais no armazenamento seguro do Android e, ao abrir
  de novo, já sabe que está pareada.
- Especificação do protocolo em `docs/protocolo.md`.

## [0.3.0] — Fase 3: autenticação do administrador

### Adicionado

- Configuração inicial: quem abre o painel pela primeira vez cria o
  administrador. Não existe senha padrão; a senha é guardada com bcrypt.
- Login e logout com sessão em cookie `HttpOnly` e `SameSite=Strict`, válida
  por 7 dias. O banco guarda só o hash do token.
- Limite de 5 logins errados por minuto por IP (resposta `429`).
- Requisições que alteram dados vindas de outra origem são recusadas
  (proteção contra CSRF).
- Dashboard com telas de configuração inicial, login e painel provisório.

## [0.2.0] — Fase 2: núcleo do servidor

### Adicionado

- Configuração do servidor por argumentos ou variáveis de ambiente: porta,
  pasta de dados, pasta do dashboard e nível de log (veja o `.env.example`).
- Banco SQLite em `data/beyond.db` com migrações versionadas e aplicadas na
  inicialização.
- Esquema inicial: configurações do servidor, administrador, sessões, grupos
  e TVs.
- Logs estruturados (logfmt) e erros da API padronizados em JSON.
- O servidor serve o dashboard compilado em `http://localhost:8787/`.

### Alterado

- O servidor passa a exigir Dart ≥ 3.10.

## [0.1.0] — Fase 1: esqueleto do monorepo

### Adicionado

- Workspace Dart na raiz, reunindo servidor, dashboard, app da TV e protocolo.
- Pacote `beyond_protocol` com o envelope de mensagens versionado.
- Servidor `shelf` com a rota `/health`.
- Dashboard Flutter Web vazio.
- App Flutter Android TV com manifesto *leanback* e banner.
- CI no GitHub Actions: formatação, análise, testes, APK de debug e gitleaks.
- Guia de como rodar cada app localmente no README.

## [0.0.0] — Fase 0: fundação do repositório

### Adicionado

- `.gitignore` com proteções para repositório público.
- Plano de desenvolvimento, README, licença MIT, `SECURITY.md` e
  `CONTRIBUTING.md`.
- ADRs 0001–0004 (Dart full-stack, workspace, SQLite e descoberta UDP).
- `.editorconfig` e templates de issue e PR.
