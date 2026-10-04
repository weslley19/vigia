# Vigia

Monitor de uso da máquina para macOS, que vive na barra de menu.

Mostra CPU, memória, disco, rede, bateria e os processos mais pesados num popover leve. É um projeto pessoal, feito para uso próprio, sem loja e sem conta de desenvolvedor.

## Funcionalidades

A barra de menu mostra o **uso de CPU** em tempo real. Ao clicar, o popover exibe:

- **CPU:** uso total e uma barra por núcleo.
- **Memória:** usada / total (mesma conta do Monitor de Atividade: app + fixa + comprimida) e a **pressão** de memória.
- **Disco:** espaço livre e ocupação.
- **Rede:** velocidade de download e upload.
- **Bateria:** nível, se está carregando ou na tomada, ciclos e **capacidade máxima** (o mesmo número dos Ajustes do Sistema).
- **Top 5 processos** por CPU ou por memória, agrupados por app (todos os helpers do Chrome, por exemplo, somam numa linha).

As barras mudam de cor conforme o uso: verde, laranja e vermelho.

### Ajustes

A engrenagem no cabeçalho abre os ajustes, com um **switch para cada monitoramento**. A escolha fica salva.

- **Top 5 processos vem desligado por padrão**, por ser a leitura mais pesada. Os demais vêm ligados.
- Monitoramentos desligados **não são lidos**, então não gastam recurso.
- Se a CPU estiver desligada, o número some da barra de menu.

## Como funciona

Um timer atualiza as leituras a cada **5 segundos**. Tudo vem de APIs do próprio macOS, sem bibliotecas externas:

| Dado | Fonte |
|---|---|
| CPU | `host_processor_info` (diferença de ticks entre leituras) |
| Memória | `host_statistics64` + `sysctl kern.memorystatus_vm_pressure_level` |
| Disco | `URLResourceValues` |
| Rede | `getifaddrs` (interfaces `en*`) |
| Bateria | `IOKit` (`IOPowerSources` e `AppleSmartBattery`) |
| Processos | `libproc` (`proc_listpids`, `proc_pidinfo`) |
| Capacidade máxima | `system_profiler`, consultado **uma vez por dia** |

Consumo medido: ~0% de CPU e ~45 MB de memória com o popover fechado.

```
Vigia/
  VigiaApp.swift          # MenuBarExtra + número de CPU na barra
  SystemMonitor.swift     # estado observável e timer de amostragem
  SystemSamplers.swift    # leituras de baixo nível do sistema
  Module.swift            # os monitoramentos ligáveis (ajustes)
  DashboardView.swift     # popover, cartões e ajustes
```

## Stack

- Swift / SwiftUI
- `MenuBarExtra` (estilo janela) e `@Observable`
- macOS 26.5 (deployment target atual)

## Observações

- O **App Sandbox está desligado**. Com ele ligado o macOS não deixa ler os processos de outros apps. Isso impede distribuir pela App Store, mas não afeta o uso pessoal.
- Processos de outros usuários (root) não aparecem na lista de processos, porque exigem privilégio.

## Rodando

1. Abra `Vigia.xcodeproj` no Xcode.
2. Aperte **⌘R**. O medidor aparece na barra de menu.

Como o app não tem Dock, o ⌘Q não funciona: use o botão **Sair** do popover ou o ■ Stop do Xcode.

## Instalando para uso diário

Sem conta paga da Apple, o Xcode assina o app localmente (Team = None), o que basta para rodar no próprio Mac.

```bash
pkill -x Vigia
xcodebuild -project Vigia.xcodeproj -scheme Vigia -configuration Release -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/Vigia-*/Build/Products/Release/Vigia.app /Applications/
open /Applications/Vigia.app
```

Na primeira abertura, se o macOS reclamar de "desenvolvedor não identificado", clique com o botão direito no app → **Abrir**.

Para abrir junto com o sistema: **Ajustes do Sistema → Geral → Itens de Início**.

## Ideias futuras

- Mini-gráficos com o histórico dos últimos minutos.
- Temperatura e ventoinhas.
- Alertas quando disco ou memória passarem de um limite.
- Intervalo de atualização configurável nos ajustes.
