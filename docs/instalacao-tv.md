# Instalação na TV

Guia para instalar o app Beyond TV numa Android TV ou TV box (Android 7 ou
mais novo) e deixá-lo abrindo sozinho. Os exemplos usam `192.168.0.10` como IP
da TV; troque pelo IP da sua.

## 1. Obter o APK

Há três caminhos, do mais simples ao mais trabalhoso:

- **Release do GitHub:** baixe o `beyond-tv-<versão>.apk` da página de
  releases do repositório (a partir da versão 1.0).
- **Artefato do CI:** em cada push ou PR, o job "APK de debug" guarda o
  arquivo `beyond-tv-debug-apk` por 7 dias. Abra o run em *Actions*, desça até
  *Artifacts* e baixe. O APK de debug serve para testes; não use em produção.
- **Compilar:** com o Flutter e o Android SDK instalados, rode
  `flutter build apk --release` em `apps/tv/`. O arquivo sai em
  `apps/tv/build/app/outputs/flutter-apk/app-release.apk`. Para assinar com a
  sua chave, veja a seção 6.

## 2. Instalar com adb (pela rede)

1. Na TV, abra *Configurações → Preferências do dispositivo → Sobre* e clique
   sete vezes em *Build* para liberar as opções de desenvolvedor. O caminho
   muda um pouco entre fabricantes.
2. Em *Opções do desenvolvedor*, ative *Depuração USB* e, se existir,
   *Depuração pela rede* (ou *ADB pela rede*).
3. No computador, na mesma rede:

   ```sh
   adb connect 192.168.0.10:5555
   adb install -r beyond-tv.apk
   ```

   Na primeira conexão, a TV pede para autorizar o computador. Aceite.
4. Abra o app pela home da TV (ele aparece na fileira de apps) ou com
   `adb shell am start -n dev.beyondtv.beyond_tv/.MainActivity`.

`-r` reinstala por cima e mantém o pareamento. Só funciona se o APK novo foi
assinado com a mesma chave do instalado.

## 3. Instalar com pen drive

1. Copie o APK para um pen drive e conecte na TV.
2. Instale um gerenciador de arquivos pela loja da TV, se ela não tiver um
   (por exemplo, o *File Commander* ou o *X-plore*).
3. Em *Configurações → Segurança e restrições → Fontes desconhecidas*, permita
   que esse gerenciador instale apps.
4. Abra o pen drive no gerenciador, selecione o APK e confirme a instalação.

## 4. Primeiro uso

1. Deixe o servidor rodando no PC (veja o README) e conecte a TV na mesma
   rede.
2. Abra o app. Ele procura o servidor sozinho; se não achar, use *Digitar IP*.
3. Escolha o servidor. A TV mostra um código de 4 dígitos e aparece no painel
   em *Aguardando aprovação*. Confira se o código é o mesmo e clique em
   *Aprovar*. Depois, renomeie a TV no painel.

   Prefere digitar um código? Na TV, escolha *Digitar código*; no painel,
   clique em *Adicionar TV* e digite na TV o código de 6 caracteres que
   aparecer. Servidores 1.0 só aceitam esse caminho, e a TV vai direto para
   ele.

## 5. Abrir sozinho ao ligar

O app tenta abrir depois que a TV liga. Até o Android 9 isso funciona sem
nada extra. **No Android 10 ou mais novo**, o sistema bloqueia apps que se
abrem sozinhos, e é preciso uma destas duas opções, ambas no **menu oculto**
(aperte ⬆ ⬆ ⬇ ⬇ no controle, ou segure OK por 2 segundos, com a TV pareada):

- **Permitir sobreposição:** abre a tela *Sobrepor a outros apps*; ative para
  o Beyond TV. Algumas TVs não têm essa tela. Nesse caso, conceda pelo adb:

  ```sh
  adb shell appops set dev.beyondtv.beyond_tv SYSTEM_ALERT_WINDOW allow
  ```

- **Modo quiosque:** o app passa a poder ser o launcher (a "home") da TV.
  Ligue *Modo quiosque* e depois *Escolher launcher padrão*, e selecione o
  Beyond TV. A TV então liga direto no app, e o botão Voltar não sai dele.

No mesmo menu, *Abrir ao ligar a TV* desliga esse comportamento.

### Sair do modo quiosque

Abra o menu oculto e desligue *Modo quiosque*: o app deixa de ser candidato a
launcher e a TV volta para a home original. Se o menu não abrir, pelo adb:

```sh
adb shell pm disable-user dev.beyondtv.beyond_tv/.KioskLauncher
```

## 6. Assinatura de release

O APK de release precisa sempre da **mesma chave**: uma chave diferente
impede a atualização por cima, e a TV teria de desinstalar o app e parear de
novo. A chave fica **fora do repositório**.

1. Gere a chave uma vez e guarde-a com backup:

   ```sh
   keytool -genkey -v -keystore ~/chaves/beyond-tv-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias beyond-tv
   ```

2. Copie `apps/tv/android/key.properties.example` para
   `apps/tv/android/key.properties` (ignorado pelo git) e preencha o caminho
   da chave, o alias e as senhas.
3. Rode `flutter build apk --release` em `apps/tv/`.

Sem o `key.properties`, o build de release usa a chave de debug, que serve
para testar mas não para distribuir.

## Problemas comuns

| Sintoma | O que fazer |
|---------|-------------|
| A TV não acha o servidor | Confira se estão na mesma rede e se o firewall do PC libera `8787/tcp` e `8788/udp`. Use *Digitar IP*. |
| `adb connect` falha | Confirme a depuração pela rede, o IP da TV e que a porta é `5555`. Algumas TVs só aceitam depois de conectar uma vez por USB. |
| "App não instalado" ao atualizar | O APK novo tem outra assinatura. Desinstale o antigo (`adb uninstall dev.beyondtv.beyond_tv`) e pareie de novo. |
| O app não abre sozinho | Veja a seção 5. Algumas TVs também têm uma lista de "apps de inicialização" nas configurações. |
| Tela preta num vídeo | O codec pode não ser suportado pela TV. Prefira MP4 com H.264. |
