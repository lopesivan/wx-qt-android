#!/usr/bin/env bash

################################################################################
# Script Unificado de Build - wxWidgets + Qt para Android
# Consolida: all.sh, wx-build, app-build e scripts auxiliares
################################################################################

set -e # Encerra em caso de erro
set -u # Trata variáveis não definidas como erro

################################################################################
# CONFIGURAÇÕES GLOBAIS
################################################################################

echo "=========================================="
echo "Inicializando Configurações do Ambiente"
echo "=========================================="

# Diretório base do projeto
BASE_PATH="${PWD}"

# Configurações do Android NDK e SDK
NDK_VERSION=21.4.7075529
ANDROID_SDK_ROOT="$HOME/Android/Sdk"
ANDROID_NDK_ROOT="${ANDROID_SDK_ROOT}/ndk/${NDK_VERSION}"
CONF_ANDROID_LEVEL=28
ANDROID_NDK_PLATFORM="android-${CONF_ANDROID_LEVEL}"

# Arquiteturas Android a serem compiladas
CONF_ANDROID_ARCHES="x86_64 arm64-v8a"
CONF_ANDROID_ARCHES="arm64-v8a"

# Diretórios de ferramentas customizadas
QT5_CUSTOM_DIR="${BASE_PATH}/qt/5.15.2/android"
PATCHELF="${BASE_PATH}/patchelf"
WX_ROOT="${BASE_PATH}/wxWidgets"
CONF_SYSROOT="${BASE_PATH}/sysroot"
NDKDEPENDS="${BASE_PATH}/ndk-depends"

# Configurações do wxWidgets
WX_VERSION=3.3
WX_INC_DIR="${WX_ROOT}/include"

# Adiciona ferramentas ao PATH
export PATH="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/bin:${QT5_CUSTOM_DIR}/bin:$PATH"

# Cria diretório sysroot se não existir
mkdir -p "${CONF_SYSROOT}"

echo "✓ Configurações carregadas com sucesso"
echo ""

################################################################################
# FUNÇÃO: Configurar Variáveis Específicas da Arquitetura
################################################################################

setup_arch_environment() {
    local arch=$1

    echo "  → Configurando ambiente para arquitetura: ${arch}"

    local CONF_ANDROID_ARCH="${arch}"

    # Mapeia nome da arquitetura Android para nome do compilador
    case ${CONF_ANDROID_ARCH} in
        arm64-v8a)
            CONF_COMPILER_ARCH="aarch64"
            ;;
        *)
            CONF_COMPILER_ARCH="${CONF_ANDROID_ARCH}"
            ;;
    esac

    export WX_CONFHOST="${CONF_COMPILER_ARCH}-linux-android${CONF_ANDROID_LEVEL}"

    # Estrutura de diretórios específica da arquitetura
    export CONF_SYSROOT_ARCH="${CONF_SYSROOT}/${CONF_ANDROID_ARCH}"
    export CONF_SYSROOT_USR="${CONF_SYSROOT_ARCH}/usr"

    # Cria estrutura de diretórios
    mkdir -p "${CONF_SYSROOT_USR}"/{lib,include,bin}

    echo "    ✓ Arquitetura ${arch} configurada"
}

################################################################################
# FUNÇÃO: Limpar e Preparar wxWidgets
################################################################################

clean_wxwidgets() {
    echo "=========================================="
    echo "Limpando e Preparando wxWidgets"
    echo "=========================================="

    mkdir -p "${WX_ROOT}"

    git submodule init

    pushd "${WX_ROOT}" >/dev/null

    echo "  → Atualizando submódulos do wxWidgets..."
    git submodule update --init --recursive

    popd >/dev/null

    echo "✓ wxWidgets preparado"
    echo ""
}

################################################################################
# FUNÇÃO: Compilar wxWidgets para uma Arquitetura Específica
################################################################################

build_wxwidgets_arch() {
    local arch=$1

    echo "=========================================="
    echo "Compilando wxWidgets para ${arch}"
    echo "=========================================="

    setup_arch_environment "${arch}"

    local WX_BUILDDIR_ARCH="${WX_ROOT}/build_${CONF_ANDROID_ARCH}"
    local WX_LIB_DIR="${WX_BUILDDIR_ARCH}/lib"

    pushd "${WX_ROOT}" >/dev/null

    # Cria diretório de build
    mkdir -p "build_${CONF_ANDROID_ARCH}"
    pushd "build_${CONF_ANDROID_ARCH}" >/dev/null

    # Flags de compilação
    export CPPFLAGS=""
    export CXXFLAGS="${CPPFLAGS}"
    export CFLAGS="${CPPFLAGS}"
    export LDFLAGS="-llog -Wl,-rpath-link=${CONF_SYSROOT_USR}/lib"

    echo "  → Configurando CMake..."
    cmake --fresh \
        -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake" \
        -DCMAKE_INSTALL_PREFIX="${CONF_SYSROOT_USR}" \
        -DANDROID_PLATFORM="${ANDROID_NDK_PLATFORM}" \
        -DANDROID_ABI="${CONF_ANDROID_ARCH}" \
        -DCMAKE_FIND_ROOT_PATH="${CONF_SYSROOT_ARCH};${QT5_CUSTOM_DIR}" \
        -DCMAKE_FIND_DEBUG_MODE=ON \
        -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
        -DCMAKE_C_FLAGS="${CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
        -DwxBUILD_TOOLKIT=qt \
        -DwxUSE_SECRETSTORE=OFF \
        -DwxUSE_LIBICONV=OFF \
        -DwxUSE_INTL=ON \
        -DwxUSE_OPENGL=OFF \
        -DwxUSE_REGEX=OFF \
        ..

    echo "  → Compilando ..."
    cmake --build . --target install/strip

    popd >/dev/null

    # Copia bibliotecas compiladas
    echo "  → Copiando bibliotecas para sysroot..."
    cp "${WX_LIB_DIR}"/*.so "${CONF_SYSROOT_USR}/lib/" 2>/dev/null || true
    cp -r "${WX_LIB_DIR}/wx" "${CONF_SYSROOT_USR}/lib/" 2>/dev/null || true
    cp -r "./include/wx" "${CONF_SYSROOT_USR}/include" 2>/dev/null || true

    popd >/dev/null

    echo "✓ wxWidgets compilado para ${arch}"
    echo ""
}

################################################################################
# FUNÇÃO: Compilar wxWidgets para Todas as Arquiteturas
################################################################################

build_wxwidgets_all() {
    echo "=========================================="
    echo "Iniciando Build do wxWidgets"
    echo "=========================================="

    clean_wxwidgets

    for arch in ${CONF_ANDROID_ARCHES}; do
        build_wxwidgets_arch "${arch}"
    done

    echo "✓ wxWidgets compilado para todas as arquiteturas"
    echo ""
}

################################################################################
# FUNÇÃO: Compilar Aplicação gsoc2014
################################################################################

build_application() {
    echo "=========================================="
    echo "Compilando Aplicação gsoc2014"
    echo "=========================================="

    # Remove build anterior
    rm -rf gsoc2014/build/

    pushd gsoc2014 >/dev/null

    echo "  → Executando build.sh da aplicação..."
    ./build.sh

    popd >/dev/null

    echo "✓ Aplicação compilada"
    echo ""
}

################################################################################
# FUNÇÃO: Copiar Dependências para uma Arquitetura
################################################################################

copy_dependencies_arch() {
    local arch=$1

    echo "=========================================="
    echo "Copiando Dependências para ${arch}"
    echo "=========================================="

    setup_arch_environment "${arch}"

    pushd gsoc2014/build >/dev/null

    # Cria estrutura de diretórios Android
    mkdir -p "./android/assets/"
    mkdir -p "./android/libs/${CONF_ANDROID_ARCH}/"

    # Detecta dependências da biblioteca compilada
    echo "  → Detectando dependências..."
    local all_deps
    all_deps="$(
        ${NDKDEPENDS} \
            -L "${CONF_SYSROOT_USR}/lib" \
            -L "${QT5_CUSTOM_DIR}/lib" \
            -L "${ANDROID_TOOLCHAIN_PATH}/sysroot/usr/lib${CONF_COMPILER_ARCH}-linux-android/" \
            "./android/libs/${CONF_ANDROID_ARCH}/libgsoc2014_${CONF_ANDROID_ARCH}.so"
    )"

    echo "  → Dependências encontradas: ${all_deps}"

    # Copia cada dependência
    for dep_name in ${all_deps}; do
        local lib_path="${CONF_SYSROOT_USR}/lib/${dep_name}"
        local bin_path="${CONF_SYSROOT_USR}/bin/${dep_name}"
        local qt_path="${QT5_CUSTOM_DIR}/lib/${dep_name}"

        if [ -f "${lib_path}" ]; then
            echo "    → Copiando ${dep_name} de lib/"
            cp -v "${lib_path}" "./android/libs/${CONF_ANDROID_ARCH}/"
        elif [ -f "${bin_path}" ]; then
            echo "    → Copiando ${dep_name} de bin/"
            cp -v "${bin_path}" "./android/libs/${CONF_ANDROID_ARCH}/"
        elif [ -f "${qt_path}" ]; then
            echo "    → Copiando ${dep_name} do Qt"
            cp -v "${qt_path}" "./android/libs/${CONF_ANDROID_ARCH}/"
        fi
    done

    popd >/dev/null

    echo "✓ Dependências copiadas para ${arch}"
    echo ""
}

################################################################################
# FUNÇÃO: Preparar e Instalar APK Android
################################################################################

deploy_and_install_apk() {
    echo "=========================================="
    echo "Preparando e Instalando APK"
    echo "=========================================="

    pushd gsoc2014/build >/dev/null

    echo "  → Executando androiddeployqt..."
    androiddeployqt \
        --input android-gsoc2014-deployment-settings.json \
        --output android \
        --android-platform "${ANDROID_NDK_PLATFORM}" \
        --install

    echo "  → Iniciando aplicação no dispositivo..."
    adb shell monkey -p org.qtproject.example.gsoc2014 1

    popd >/dev/null

    echo "✓ APK instalado e iniciado com sucesso"
    echo ""
}

################################################################################
# FUNÇÃO PRINCIPAL
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  Build Android - wxWidgets + Qt + App  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Etapa 1: Compilar wxWidgets
    build_wxwidgets_all

    # Etapa 2: Compilar aplicação
    build_application

    # Etapa 3: Copiar dependências para cada arquitetura
    for arch in ${CONF_ANDROID_ARCHES}; do
        copy_dependencies_arch "${arch}"
    done

    # Etapa 4: Preparar e instalar APK
    deploy_and_install_apk

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║      BUILD CONCLUÍDO COM SUCESSO!      ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
}

################################################################################
# EXECUÇÃO
################################################################################

main "$@"

exit 0
