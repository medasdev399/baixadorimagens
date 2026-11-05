# Baixador de Imagens

Aplicativo desktop multiplataforma (Linux e Windows) desenvolvido em Flutter para download automatizado de imagens em lote a partir de listas de URLs.

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Funcionalidades Principais](#2-funcionalidades-principais)
3. [Arquitetura e Estrutura de Arquivos](#3-arquitetura-e-estrutura-de-arquivos)
4. [Manual de Utilização](#4-manual-de-utilização)
5. [Funcionamento Interno do Motor de Download](#5-funcionamento-interno-do-motor-de-download)
6. [Requisitos de Desenvolvimento](#6-requisitos-de-desenvolvimento)
7. [Compilação e Geração de Instaladores](#7-compilação-e-geração-de-instaladores)

---

## 1. Visão Geral

O **Baixador de Imagens** permite que o usuário cole uma lista de endereços HTTP/HTTPS de imagens e realize o download concorrente para uma pasta local. O sistema gerencia fila de execução, progresso individual e global, tratamento de falhas de rede, detecção automática de extensão de arquivo e padronização dos nomes salvos em disco.

---

## 2. Funcionalidades Principais

- **Processamento em Lote**: Leitura de múltiplas URLs simultaneamente (uma URL por linha).
- **Concorrência Configurável**: Controle deslizante para definir de 1 a 20 trabalhadores (*workers*) paralelos.
- **Retentativa Automática (Retry)**: Até 3 tentativas automáticas por imagem em caso de erro de rede ou *timeout*, com intervalo progressivo de espera (*backoff* de 2 e 4 segundos).
- **Cancelamento Imediato**: Interrupção instantânea das conexões ativas via `CancelToken`, retornando os itens interrompidos para o estado pendente sem perdê-los da fila.
- **Reprocessamento Seletivo**: Botão dedicado ("Tentar Erros") para reexecutar apenas os itens que falharam após o término da fila.
- **Preservação de Estado**: Editar ou acrescentar novas URLs à lista mantém o estado dos itens que já foram concluídos anteriormente.
- **Detecção Inteligente de Formato**: Identifica a extensão real da imagem através do cabeçalho HTTP `Content-Type` (`JPEG`, `PNG`, `WebP`, `GIF`, `SVG`, `AVIF`), utilizando a extensão da URL ou `.jpg` como alternativa.
- **Prevenção de Bloqueio (Anti-Hotlink)**: Envia cabeçalhos `User-Agent` compatíveis com navegadores modernos e define automaticamente o cabeçalho `Referer` com a origem (`scheme://host/`) de cada URL.
- **Nomenclatura Sequencial Segura**: Sanitiza caracteres inválidos do nome original e aplica um prefixo numérico de 4 dígitos (`0001_nome_original.ext`), mantendo a ordem da lista e evitando sobrescrita de arquivos com nomes iguais.

---

## 3. Arquitetura e Estrutura de Arquivos

```text
baixadorimagens/
├── .github/
│   └── workflows/
│       └── build_installers.yml      # Pipeline de CI/CD (GitHub Actions) para Linux e Windows
├── installer/
│   ├── build_linux_deb.sh            # Script gerador do pacote .deb e .tar.gz para Linux
│   └── windows_setup.iss             # Script do Inno Setup gerador do instalador .exe para Windows
├── lib/
│   ├── main.dart                     # Inicialização do app e interface gráfica (DownloaderScreen)
│   └── services/
│       └── downloader_engine.dart    # Motor de download, controle de concorrência e regras de arquivo
├── linux/                            # Código nativo C++/GTK para compilação no Linux
├── windows/                          # Código nativo C++/Win32 para compilação no Windows
├── test/
│   └── widget_test.dart              # Testes automatizados da interface e montagem da fila
├── analysis_options.yaml             # Regras de análise estática e lint do Dart/Flutter
└── pubspec.yaml                      # Definição do pacote e dependências (dio, file_picker)
```

### Responsabilidades dos Módulos Principais

- **`lib/main.dart`**:
  - `BaixadorImagensApp`: Configura o tema escuro (Material 3) e inicializa a tela principal.
  - `DownloaderScreen` / `_DownloaderScreenState`: Gerencia o estado da interface, campos de texto, seleção de diretório nativo via `file_picker` e sincronização das atualizações de progresso com a taxa de atualização de quadros da tela (`SchedulerBinding`).
- **`lib/services/downloader_engine.dart`**:
  - `DownloadStatus`: Enumeração dos estados possíveis de um item (`idle`, `downloading`, `completed`, `error`).
  - `DownloadItem`: Modelo de dados que representa cada URL na fila, seu índice, progresso (`0.0` a `1.0`), nome do arquivo salvo e mensagem de erro.
  - `DownloaderEngine`: Classe responsável pelas requisições HTTP via `Dio`, controle de fila concorrente, validação de URI, gravação em disco e cancelamento.

---

## 4. Manual de Utilização

### Passo 1: Inserir a Lista de URLs
No painel esquerdo, localize o campo **Lista de URLs (uma por linha)** e cole os endereços das imagens.
- Apenas linhas não vazias iniciadas com `http` ou `https` são adicionadas à fila.
- À medida que as URLs são coladas, a fila no painel direito é montada automaticamente com a numeração sequencial (`#1`, `#2`, etc.).

### Passo 2: Definir a Pasta de Destino
Por padrão, o aplicativo utiliza a pasta `Downloads/baixadorimagens` dentro do diretório do usuário (`HOME` no Linux ou `USERPROFILE` no Windows).
- Você pode digitar outro caminho manualmente no campo **Pasta de Destino** ou clicar no botão ao lado do campo para selecionar uma pasta pelo explorador de arquivos do sistema.
- Caso a pasta informada não exista, ela será criada automaticamente ao iniciar o download.

### Passo 3: Ajustar os Downloads Simultâneos
Utilize o controle deslizante **Downloads simultâneos** para definir quantas imagens serão baixadas ao mesmo tempo (padrão: `8`, mínimo: `1`, máximo: `20`).

### Passo 4: Iniciar, Pausar/Parar e Retentar
- **Baixar Tudo**: Inicia o processamento de todos os itens que ainda não estão concluídos.
- **Parar**: Cancela imediatamente as transferências em andamento. Os itens interrompidos voltam ao estado de espera e podem ser retomados clicando novamente em **Baixar Tudo**.
- **Tentar Erros**: Botão exibido automaticamente quando uma ou mais URLs falham após todas as tentativas. Ao acioná-lo, apenas os itens com status de erro são reprocessados.

### Estados dos Itens na Fila (Painel Direito)
- **Aguardando (Ícone de relógio cinza)**: Item na fila aguardando um trabalhador livre.
- **Baixando (Indicador circular e barra de progresso)**: Transferência em andamento com progresso percentual em tempo real.
- **Concluído (Ícone de confirmação verde-água)**: Imagem salva no disco; o título passa a exibir o nome final do arquivo gerado.
- **Erro (Ícone de alerta vermelho)**: Falha no download; o subtítulo exibe o motivo da falha (URL inválida, erro HTTP ou tempo esgotado).

---

## 5. Funcionamento Interno do Motor de Download

### Parâmetros de Rede
| Parâmetro | Valor Configurado | Descrição |
| :--- | :--- | :--- |
| `connectTimeout` | 15 segundos | Tempo máximo para estabelecer a conexão com o servidor. |
| `receiveTimeout` | 30 segundos | Tempo máximo para recepção dos dados da imagem. |
| `followRedirects` | `true` | Segue redirecionamentos HTTP (301, 302, 307, 308) automaticamente. |
| Tentativas máximas | 3 por item | Erros de rede aguardam `2s` na 1ª falha e `4s` na 2ª falha antes de desistir. |

*Nota: URLs com formato sintático inválido falham imediatamente na primeira verificação, sem realizar retentativas desnecessárias.*

### Mapeamento de Tipos MIME (`Content-Type`)
| Cabeçalho `Content-Type` | Extensão Aplicada |
| :--- | :--- |
| `image/jpeg` | `.jpg` |
| `image/png` | `.png` |
| `image/webp` | `.webp` |
| `image/gif` | `.gif` |
| `image/svg+xml` | `.svg` |
| `image/avif` | `.avif` |
| Outros / Ausente | Extensão extraída da URL ou `.jpg` (padrão) |

### Regra de Formatação do Nome do Arquivo
1. Extrai o último segmento do caminho da URL (ou utiliza `img` caso não exista).
2. Remove caracteres especiais mantendo apenas letras, números, hifens (`-`) e sublinhados (`_`).
3. Prefixa com o índice do item na fila preenchido com zeros à esquerda (4 dígitos).
4. Exemplo: O item `#12` de `https://exemplo.com/fotos/produto final (1).webp` será salvo como `0012_produtofinal1.webp`.

---

## 6. Requisitos de Desenvolvimento

### Pré-requisitos
- **Flutter SDK**: Canal `stable` (Dart SDK `^3.13.2`).
- **No Linux (Ubuntu/Debian)**:
  ```bash
  sudo apt-get update
  sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
  ```
- **No Windows**:
  - Visual Studio 2022 ou Build Tools com a carga de trabalho "Desenvolvimento para desktop com C++".

### Comandos Úteis
```bash
# Baixar dependências do projeto
flutter pub get

# Executar em modo de desenvolvimento no Linux
flutter run -d linux

# Executar em modo de desenvolvimento no Windows
flutter run -d windows

# Executar testes automatizados
flutter test
```

---

## 7. Compilação e Geração de Instaladores

### 7.1. Compilação Local no Linux
Para compilar o binário otimizado de produção e gerar o pacote `.deb` e a versão portátil `.tar.gz` na pasta `dist/`:

```bash
flutter build linux --release
./installer/build_linux_deb.sh 1.0.0
```

Arquivos gerados em `dist/`:
- `BaixadorImagens-Linux-x64.deb`: Instalável via `sudo apt install ./dist/BaixadorImagens-Linux-x64.deb` ou `sudo dpkg -i dist/BaixadorImagens-Linux-x64.deb`.
- `BaixadorImagens-Linux-x64-Portable.tar.gz`: Pacote portátil que pode ser extraído e executado em qualquer distribuição Linux.

### 7.2. Compilação Automatizada (Windows e Linux) via GitHub Actions
O projeto possui um pipeline configurado em `.github/workflows/build_installers.yml` que compila simultaneamente as versões de **Linux** e **Windows** nos servidores do GitHub.

#### Formas de Disparar a Build:
1. **Automaticamente por Push**: A cada `git push` nas branches `main` ou `master`.
2. **Manualmente**: Acessando a aba **Actions** no GitHub, selecionando **Build Installers (Linux & Windows)** e clicando em **Run workflow**.
3. **Publicação de Release (Tags)**: Ao criar e enviar uma tag iniciada por `v`:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

#### Pacotes Gerados pelo GitHub Actions:
- **Linux**:
  - `BaixadorImagens-Linux-x64.deb` (Instalador Debian/Ubuntu)
  - `BaixadorImagens-Linux-x64-Portable.tar.gz` (Portátil)
- **Windows**:
  - `BaixadorImagens-Windows-Setup.exe` (Instalador padrão Windows em Português gerado pelo Inno Setup, com suporte a atalhos e desinstalador)
  - `BaixadorImagens-Windows-x64-Portable.zip` (Portátil)
