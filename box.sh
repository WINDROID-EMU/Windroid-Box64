#!/bin/bash

# Script de automação para compilar o Box64 para MiceWine (ANDROID Release)
# Baseado no workflow "Package Rat File for MiceWine" do arquivo release.yml.

# --- Configurações ---
REPO_URL="https://github.com/ptitSeb/box64.git"
REPO_DIR="box64"
BUILD_DIR="build"
NDK_VERSION="r26b"
NDK_ZIP="android-ndk-${NDK_VERSION}-linux.zip"
NDK_DIR="android-ndk-${NDK_VERSION}"
TERMUX_DOCKER_REPO="https://github.com/termux/termux-docker.git"

# Variáveis de compilação para ANDROID Release (MiceWine)
PLATFORM="ANDROID"
CMAKE_BUILD_TYPE="Release"
# BOX64_COMPILER será definido após o download do NDK
# BOX64_PLATFORM_MACRO será definido após o download do NDK

# Nome do artefato final
ARTIFACT_NAME="box64-MiceWine-${CMAKE_BUILD_TYPE}.rat"

echo "Iniciando a automação para compilar o Box64 para MiceWine ($PLATFORM - $CMAKE_BUILD_TYPE)..."

# 1. Atualização e Instalação de Dependências
echo "1. Instalando dependências necessárias (git, cmake, make, python3, patchelf, p7zip, unzip, zip)..."
# Adicionando '7zip' para a compactação do artefato .rat
sudo apt-get update
if sudo apt-get install -y git cmake make python3 patchelf p7zip unzip zip; then
    echo "Dependências instaladas com sucesso."
else
    echo "ERRO: Falha ao instalar dependências."
    exit 1
fi

# 2. Clonar ou Atualizar o Repositório Box64
echo "2. Clonando ou atualizando o repositório Box64..."
if [ -d "$REPO_DIR" ]; then
    echo "Diretório $REPO_DIR já existe. Atualizando o código-fonte..."
    cd "$REPO_DIR"
    git pull
else
    if git clone "$REPO_URL"; then
        echo "Repositório clonado com sucesso."
        cd "$REPO_DIR"
    else
        echo "ERRO: Falha ao clonar o repositório $REPO_URL."
        exit 1
    fi
fi

# 3. Configuração do Ambiente (NDK e Termux) - Baseado em release.yml
echo "3. Configurando o ambiente de compilação Android (NDK e Termux)..."

# Baixar e extrair o Android NDK
if [ ! -d "$NDK_DIR" ]; then
    echo "Baixando Android NDK $NDK_VERSION..."
    wget -q "https://dl.google.com/android/repository/$NDK_ZIP"
    echo "Extraindo NDK..."
    unzip -qq "$NDK_ZIP"
    rm "$NDK_ZIP"
else
    echo "Android NDK já existe."
fi

# Definir variáveis de ambiente para o compilador e macros
NDK_TOOLCHAIN_PATH="$PWD/$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
BOX64_COMPILER="$NDK_TOOLCHAIN_PATH/aarch64-linux-android31-clang"
BOX64_PLATFORM_MACRO="-DANDROID=1 -DARM_DYNAREC=1 -DBAD_SIGNAL=1"

# Clonar e configurar dependências do Termux (simulando as linhas 186-189)
if [ ! -d "termux-docker" ]; then
    echo "Clonando termux-docker..."
    git clone "$TERMUX_DOCKER_REPO"
fi

echo "Simulando configuração de arquivos do Termux..."
if [ -d "termux-docker/system/arm" ]; then
    mkdir -p local_system
    sudo cp -rf termux-docker/system/arm local_system/
    sudo chown -R $(whoami):$(whoami) local_system/arm
    sudo chmod 755 -R local_system/arm
    echo "Arquivos do Termux copiados para local_system/arm."
else
    echo "AVISO: Diretório termux-docker/system/arm não encontrado. A compilação pode falhar."
fi

# 4. Configuração e Compilação (Clean Build)
echo "4. Configurando e compilando o Box64 (Clean Build)..."

# Criar e entrar no diretório de build
if [ -d "$BUILD_DIR" ]; then
    echo "Removendo diretório de build anterior para compilação limpa..."
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Comando CMake
CMAKE_COMMAND="cmake .. \
    -DCMAKE_C_COMPILER=$BOX64_COMPILER \
    $BOX64_PLATFORM_MACRO \
    -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
    -DHAVE_BACKTRACE:BOOL=OFF \
    -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCI=OFF" # Desabilitando a flag CI para compilação local

echo "Executando CMake..."
echo "$CMAKE_COMMAND"

if $CMAKE_COMMAND; then
    echo "Configuração CMake concluída. Iniciando a compilação..."
    # Comando Make
    if make -j$(nproc) VERBOSE=1; then
        echo "Compilação do Box64 concluída com sucesso!"
        
        # 5. Empacotamento do Binário para MiceWine (.rat file)
        echo "5. Empacotando o binário 'box64' em $ARTIFACT_NAME (formato MiceWine)..."
        
        # Voltamos para o diretório raiz do projeto para o empacotamento
        cd ..
        
        # Criando a estrutura de diretórios necessária
        mkdir -p "$BUILD_DIR/files/usr/bin"
        
        # Copiando o binário
        cp "$BUILD_DIR/box64" "$BUILD_DIR/files/usr/bin"
        
        # Criando o arquivo pkg-header (linhas 452-456)
        # Precisamos obter a versão do Box64 e o short commit
        BOX64_VERSION=$(cat src/box64version.h | grep BOX64_MAJOR | cut -d " " -f 3).$(cat src/box64version.h | grep BOX64_MINOR | cut -d " " -f 3).$(cat src/box64version.h | grep BOX64_REVISION | cut -d " " -f 3)
        SHORT_COMMIT=$(git rev-parse --short HEAD)
        
        cat <<EOF > "$BUILD_DIR/pkg-header"
name=Box64 (CI Build)
category=Box64
version=${BOX64_VERSION}-${SHORT_COMMIT}
architecture=aarch64
vkDriverLib=
EOF
        
        # Compactando o arquivo .rat (linha 458)
        # O comando '7z' é usado no workflow, então o usamos aqui
        cd "$BUILD_DIR"
        if 7z a -tzip -mx=5 "../$ARTIFACT_NAME" files pkg-header; then
            echo "Artefato MiceWine (.rat) criado com sucesso: $(pwd)/../$ARTIFACT_NAME"
        else
            echo "AVISO: Falha ao criar o arquivo .rat. O binário ainda está disponível em $(pwd)/box64."
        fi
        
    else
        echo "ERRO: Falha durante a compilação (make)."
        exit 1
    fi
else
    echo "ERRO: Falha na configuração CMake."
    exit 1
fi

# 6. Finalização
cd ../.. # Volta para o diretório inicial
echo "Automação concluída."
echo "O artefato final para MiceWine está em: $(pwd)/$ARTIFACT_NAME"

exit 0

