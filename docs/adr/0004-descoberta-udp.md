# 0004. Descoberta do servidor por UDP broadcast

- **Status:** Aceita
- **Data:** 2026-10-13

## Contexto

Digitar o IP do PC na TV com o controle remoto é chato e sujeito a erro, e o IP
pode mudar com o DHCP. A TV precisa achar o servidor sozinha. O mDNS seria a
opção padrão, mas responder mDNS a partir do Windows em Dart puro é instável
(conflito com o serviço do sistema na porta 5353).

## Decisão

- A TV envia um **UDP broadcast** com `BEYONDTV_DISCOVER v1` para a porta
  `8788/udp`.
- O servidor responde em unicast com `{ v, name, port, serverId }`. O IP
  não vai na resposta: a TV usa o endereço de origem do pacote, que é sempre
  o IP do servidor na rede da TV, mesmo num PC com várias placas de rede.
- A tela da TV sempre oferece **"Digitar IP"** como alternativa.
- Ao perder a conexão, a TV refaz a descoberta antes de desistir.

## Consequências

- ✅ Implementação simples em Dart puro dos dois lados.
- ✅ Funciona sem configurar nada na maioria das redes domésticas e pequenas.
- ⚠️ Broadcast não atravessa roteadores: PC e TVs precisam estar na mesma
  sub-rede.
- ⚠️ Redes com isolamento de clientes no Wi-Fi bloqueiam a descoberta; nesse
  caso, o IP manual resolve.
- ⚠️ Qualquer dispositivo da sub-rede descobre o servidor. Isso não dá acesso a
  nada: o pareamento continua exigindo o código gerado no dashboard.
- ⚠️ É preciso liberar `8788/udp` no Firewall do Windows.
